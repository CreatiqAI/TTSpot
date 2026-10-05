// Fringe clean-up for Kie's transparent renders (design/toy_car/clean.py, in
// Deno). Raw GPT Image 2 output keeps a semi-transparent, colour-tinted halo
// around the subject; on a light card it reads as a dirty outline.
//
//   1. alpha < 150 → 0, else 255 (hard edge, no halo)
//   2. crop to the bounding box of what is left
//   3. box-filter downscale to `width` px wide (800 by default; never upscales)
//
// imagescript decodes and encodes the PNG (zlib in wasm); the pixel work is
// plain typed-array loops so it stays fast and predictable.
import { Image } from "https://deno.land/x/imagescript@1.3.0/mod.ts";

export const ALPHA_CUT = 150;
export const TOY_WIDTH = 800;

export type CleanReport = {
  inWidth: number;
  inHeight: number;
  outWidth: number;
  outHeight: number;
  outBytes: number;
  decodeMs: number;
  pixelsMs: number;
  encodeMs: number;
  totalMs: number;
  /** Share of the output pixels that are opaque (0..1); ~0 means nothing was found. */
  coverage: number;
};

export class EmptyImageError extends Error {
  constructor() {
    super("Nothing left after the alpha cut");
  }
}

export async function cleanToy(png: Uint8Array, width = TOY_WIDTH): Promise<{ png: Uint8Array; report: CleanReport }> {
  const t0 = performance.now();
  const decoded = await Image.decode(png);
  if (!(decoded instanceof Image)) throw new Error("Not a still image");
  const t1 = performance.now();

  const w = decoded.width, h = decoded.height;
  const src = decoded.bitmap; // RGBA, row-major
  // 1. threshold + bounding box in one pass
  let minX = w, minY = h, maxX = -1, maxY = -1;
  for (let y = 0; y < h; y++) {
    let row = y * w * 4;
    for (let x = 0; x < w; x++, row += 4) {
      if (src[row + 3] < ALPHA_CUT) {
        src[row + 3] = 0;
      } else {
        src[row + 3] = 255;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) throw new EmptyImageError();

  // 2 + 3. crop and box-filter downscale straight from the source buffer.
  const cw = maxX - minX + 1, ch = maxY - minY + 1;
  const scale = cw > width ? width / cw : 1;
  const ow = Math.max(1, Math.round(cw * scale)), oh = Math.max(1, Math.round(ch * scale));
  const out = new Image(ow, oh);
  const dst = out.bitmap;
  let opaque = 0;
  for (let oy = 0; oy < oh; oy++) {
    const sy0 = minY + Math.floor(oy / scale), sy1 = Math.min(maxY + 1, minY + Math.max(1, Math.ceil((oy + 1) / scale)));
    for (let ox = 0; ox < ow; ox++) {
      const sx0 = minX + Math.floor(ox / scale), sx1 = Math.min(maxX + 1, minX + Math.max(1, Math.ceil((ox + 1) / scale)));
      // Alpha-weighted average: transparent pixels must not darken the edge.
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let sy = sy0; sy < sy1; sy++) {
        let i = (sy * w + sx0) * 4;
        for (let sx = sx0; sx < sx1; sx++, i += 4) {
          const al = src[i + 3];
          if (al) {
            r += src[i];
            g += src[i + 1];
            b += src[i + 2];
            a += al;
          }
          n++;
        }
      }
      const o = (oy * ow + ox) * 4;
      if (a) {
        const k = a / 255; // number of opaque samples (alpha is 0 or 255 here)
        dst[o] = Math.round(r / k);
        dst[o + 1] = Math.round(g / k);
        dst[o + 2] = Math.round(b / k);
        dst[o + 3] = Math.round(a / n);
        opaque++;
      } else {
        dst[o] = dst[o + 1] = dst[o + 2] = dst[o + 3] = 0;
      }
    }
  }
  const t2 = performance.now();
  const encoded = await out.encode(3); // zlib level 3: a few hundred KB, fast
  const t3 = performance.now();
  return {
    png: encoded,
    report: {
      inWidth: w,
      inHeight: h,
      outWidth: ow,
      outHeight: oh,
      outBytes: encoded.byteLength,
      decodeMs: Math.round(t1 - t0),
      pixelsMs: Math.round(t2 - t1),
      encodeMs: Math.round(t3 - t2),
      totalMs: Math.round(t3 - t0),
      coverage: opaque / (ow * oh),
    },
  };
}
