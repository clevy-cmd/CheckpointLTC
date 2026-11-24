import type { Env } from "./env";

export async function serveMedia(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response(null, { status: 405, headers: { allow: "GET, HEAD" } });
  }
  const url = new URL(request.url);
  const file = await env.ASSETS.fetch(new Request(url.origin + url.pathname));
  if (!file.ok) return file;

  const headers = new Headers(file.headers);
  headers.set("accept-ranges", "bytes");
  const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get("range") ?? "");
  if (!range) return new Response(request.method === "HEAD" ? null : file.body, { status: 200, headers });

  const bytes = await file.arrayBuffer();
  const size = bytes.byteLength;
  let start = range[1] === "" ? size - Number(range[2]) : Number(range[1]);
  let end = range[1] === "" || range[2] === "" ? size - 1 : Number(range[2]);
  start = Math.max(0, start);
  end = Math.min(end, size - 1);
  if (Number.isNaN(start) || Number.isNaN(end) || start > end) {
    headers.set("content-range", `bytes */${size}`);
    return new Response(null, { status: 416, headers });
  }
  headers.set("content-range", `bytes ${start}-${end}/${size}`);
  headers.set("content-length", String(end - start + 1));
  return new Response(request.method === "HEAD" ? null : bytes.slice(start, end + 1), { status: 206, headers });
}
