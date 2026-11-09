import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { inflateRawSync } from "node:zlib";

export const DATASET_CSV_NAME = "Bakery_Sales_Dummy_20261010_20261108.csv";
export const DATASET_CSV_SHA256 =
  "f85b3fa09a15fbb0e0e9e2155799928a30542caee7aef145851df65699581ae4";
export const DATASET_README_SHA256 =
  "1f795cadfb2de6f98e7dc8182298c34e813eff1e531184e9a7c4f5c5b2c62764";

function sha256(value: Buffer): string {
  return createHash("sha256").update(value).digest("hex");
}

// The reviewed package has two ordinary ZIP entries with local sizes and raw
// DEFLATE. Reject other ZIP variants rather than silently reading the wrong CSV.
export function readReviewedPackage(zipPath: string): string {
  const zip = readFileSync(zipPath);
  if (zip.length > 2_000_000) throw new Error("The ZIP is unexpectedly large.");
  const entries = new Map<string, Buffer>();
  let offset = 0;
  while (offset + 30 <= zip.length && zip.readUInt32LE(offset) === 0x04034b50) {
    const flags = zip.readUInt16LE(offset + 6);
    const method = zip.readUInt16LE(offset + 8);
    const compressedSize = zip.readUInt32LE(offset + 18);
    const uncompressedSize = zip.readUInt32LE(offset + 22);
    const nameLength = zip.readUInt16LE(offset + 26);
    const extraLength = zip.readUInt16LE(offset + 28);
    const nameEnd = offset + 30 + nameLength;
    const dataStart = nameEnd + extraLength;
    const dataEnd = dataStart + compressedSize;
    if (flags !== 0 || (method !== 0 && method !== 8) ||
        uncompressedSize > 1_000_000 || dataEnd > zip.length ||
        nameEnd > zip.length) {
      throw new Error("Unsupported or damaged ZIP entry.");
    }
    const name = zip.subarray(offset + 30, nameEnd).toString("utf8");
    if (name !== DATASET_CSV_NAME && name !== "README.md" || entries.has(name)) {
      throw new Error("The ZIP contains an unexpected or duplicate entry.");
    }
    const compressed = zip.subarray(dataStart, dataEnd);
    const content = method === 8 ? inflateRawSync(compressed, {
      maxOutputLength: 1_000_000,
    }) : compressed;
    if (content.length !== uncompressedSize) {
      throw new Error("ZIP entry size does not match its header.");
    }
    entries.set(name, content);
    offset = dataEnd;
  }
  if (entries.size !== 2 ||
      sha256(entries.get("README.md")!) !== DATASET_README_SHA256 ||
      sha256(entries.get(DATASET_CSV_NAME)!) !== DATASET_CSV_SHA256) {
    throw new Error("This is not the reviewed recent dummy sales package.");
  }
  const readme = new TextDecoder("utf-8", { fatal: true })
    .decode(entries.get("README.md")!);
  if (!readme.includes("ADAPTED_DEMO") ||
      !readme.includes("DUMMY_CONSECUTIVE_DATES")) {
    throw new Error("The package README lacks the adaptation statement.");
  }
  return new TextDecoder("utf-8", { fatal: true })
    .decode(entries.get(DATASET_CSV_NAME)!);
}
