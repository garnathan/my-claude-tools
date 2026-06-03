// Generic "read files from a GitHub repo at runtime" fetcher — the drop-in that
// replaces a per-file /contents/{path} loop. Download the repo's zipball at a
// ref ONCE, unpack it in memory, and serve all readFile/listDir calls from
// in-memory maps. Referenced by the github-api-discipline skill.
//
// One small dependency (fflate, for unzip); auth + backoff are first-class.
// The FileFetcher interface is identical to a per-file fetcher, so this is a
// straight swap: build a FetchedRepo once, then read from it as many times as
// you like for the cost of a single API call.
//
//   const repo = await createGitHubFileFetcher({ repo: "owner/name", ref: "main", token });
//   const cfg  = await repo.readFile("config/app.yaml");   // 0 extra API calls
//   const dirs = await repo.listDir("config");             // 0 extra API calls

import { unzipSync, strFromU8 } from "fflate";
import { withRateLimitRetry } from "./with-rate-limit-retry.js";

/**
 * Abstraction over file access in a remote repo. Production uses the
 * GitHub-App-backed implementation below; tests can pass an in-memory map
 * implementing the same two methods.
 */
export interface FileFetcher {
  /** Returns file contents at path, or null if missing. */
  readFile(path: string): Promise<string | null>;
  /** Returns immediate child *directory* names under path. */
  listDir(path: string): Promise<string[]>;
}

export interface GitHubFileFetcherOptions {
  repo: string; // "owner/name"
  ref: string; // branch, tag, or sha
  token: string; // GitHub App installation token (preferred) or PAT
  /** Test seam — injectable fetch. Defaults to global fetch. */
  fetch?: typeof fetch;
  /** Test seam — injectable sleep. Defaults to setTimeout-based sleep. */
  sleep?: (ms: number) => Promise<void>;
  /** Max retries on rate-limit responses. Defaults to 3. */
  maxRetries?: number;
}

/**
 * Download the repo's entire zipball at `ref` ONCE, unpack with fflate, and
 * serve all subsequent readFile / listDir calls from in-memory maps. This
 * replaces a per-file /contents/{path} pattern: a tree of N files costs one
 * API call instead of N, and a throttled response is retried with backoff
 * rather than killing the caller.
 */
export async function createGitHubFileFetcher(
  opts: GitHubFileFetcherOptions,
): Promise<FileFetcher> {
  const fetchFn = opts.fetch ?? fetch;
  const sleep =
    opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const url = `https://api.github.com/repos/${opts.repo}/zipball/${encodeURIComponent(opts.ref)}`;
  const headers = {
    Authorization: `Bearer ${opts.token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };

  const res = await withRateLimitRetry(() => fetchFn(url, { headers }), {
    maxRetries: opts.maxRetries ?? 3,
    sleep,
  });
  if (!res.ok) {
    throw new Error(
      `GitHub zipball ${opts.repo}@${opts.ref}: ${res.status} ${await res.text()}`,
    );
  }
  const raw = new Uint8Array(await res.arrayBuffer());
  const unzipped = unzipSync(raw);

  // GitHub zipballs wrap everything in a top-level dir (e.g. "owner-repo-shortsha/").
  // Detect and strip it so callers use repo-relative paths.
  const keys = Object.keys(unzipped);
  if (keys.length === 0) {
    throw new Error(`GitHub zipball ${opts.repo}@${opts.ref}: empty archive`);
  }
  const prefix = keys[0]!.split("/", 1)[0]!;
  const prefixWithSlash = `${prefix}/`;

  const filesByPath = new Map<string, Uint8Array>();
  const dirChildren = new Map<string, Set<string>>(); // dir → child names (files + dirs)

  for (const [key, content] of Object.entries(unzipped)) {
    if (!key.startsWith(prefixWithSlash)) continue;
    const rel = key.slice(prefixWithSlash.length);
    if (rel.length === 0) continue;
    const isDirEntry = rel.endsWith("/");
    const cleaned = isDirEntry ? rel.slice(0, -1) : rel;
    if (!cleaned) continue;
    if (!isDirEntry) filesByPath.set(cleaned, content);

    // Index every ancestor dir → immediate child.
    const parts = cleaned.split("/");
    for (let i = 0; i < parts.length; i += 1) {
      const parent = parts.slice(0, i).join("/");
      const child = parts[i]!;
      if (!dirChildren.has(parent)) dirChildren.set(parent, new Set());
      dirChildren.get(parent)!.add(child);
    }
  }

  const isDir = (path: string): boolean => dirChildren.has(path);

  return {
    async readFile(path) {
      const content = filesByPath.get(path);
      if (!content) return null;
      return strFromU8(content);
    },
    async listDir(path) {
      const children = dirChildren.get(path);
      if (!children) return [];
      // Immediate-subdirectory names only (mirrors a /contents dir listing).
      return [...children].filter((name) => {
        const sub = path ? `${path}/${name}` : name;
        return isDir(sub);
      });
    },
  };
}
