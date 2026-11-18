// Андройд APK-г нийтэлнэ: R2-д тогтмол нэрээр байршуулж app/version.json-ыг
// шинэчилнэ — апп нээгдэхдээ үүнийг уншиж «Шинэ хувилбар» гэж мэдэгдэнэ.
//
// Алхам:
//   1. pubspec.yaml-ийн version-ыг нэмнэ (жишээ 1.0.1+2 → 1.0.2+3; «+»-ийн
//      дараах build дугаар ЗААВАЛ өсөх ёстой).
//   2. flutter build apk --release --split-per-abi
//   3. node tool/publish_apk.js [--notes "Юу өөрчлөгдсөн"] [--min-build N]
//
// R2-ийн нууц түлхүүрийг backend-ийн .env-ээс уншина (BACKEND_DIR-ээр солино).
// --min-build: үүнээс доош build-тэй апп-ыг ЗААВАЛ шинэчлүүлнэ.
const fs = require("fs");
const path = require("path");

const appDir = path.resolve(__dirname, "..");
const backendDir = process.env.BACKEND_DIR || path.resolve(appDir, "..", "zahialgiin-system", "akifoodsBackend");
const req = (m) => require(path.join(backendDir, "node_modules", m));
req("dotenv").config({ path: path.join(backendDir, ".env"), quiet: true });
const { S3Client, PutObjectCommand } = req("@aws-sdk/client-s3");

const args = process.argv.slice(2);
const arg = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

const pubspec = fs.readFileSync(path.join(appDir, "pubspec.yaml"), "utf8");
const m = pubspec.match(/^version:\s*([0-9.]+)\+(\d+)/m);
if (!m) throw new Error("pubspec.yaml-д version: X.Y.Z+N алга");
const [, version, buildStr] = m;
const build = Number(buildStr);
const minBuild = arg("--min-build") ? Number(arg("--min-build")) : 1;
if (!(minBuild <= build)) throw new Error(`--min-build (${minBuild}) нь build (${build})-ээс их байж болохгүй`);

const env = process.env;
for (const k of ["R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET", "R2_PUBLIC_BASE_URL"]) {
  if (!env[k]) throw new Error(`${k} тохируулагдаагүй (${backendDir}/.env)`);
}
const base = env.R2_PUBLIC_BASE_URL.replace(/\/$/, "");
const client = new S3Client({
  region: "auto",
  endpoint: `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY },
});

const apkDir = path.join(appDir, "build", "app", "outputs", "flutter-apk");
const apks = [
  ["arm64", "app-arm64-v8a-release.apk", "app/akifoods-arm64.apk"],
  ["armv7", "app-armeabi-v7a-release.apk", "app/akifoods-armv7.apk"],
];

const put = (Key, Body, ContentType, extra = {}) =>
  client.send(new PutObjectCommand({ Bucket: env.R2_BUCKET, Key, Body, ContentType, CacheControl: "no-cache", ...extra }));

(async () => {
  const manifest = { build, version, minBuild, notes: arg("--notes") || "", apk: {} };
  for (const [abi, local, key] of apks) {
    const file = path.join(apkDir, local);
    // ⚠ Хуучин build-ийг шинэ дугаартайгаар нийтлэхээс сэргийлнэ.
    if (fs.statSync(file).mtimeMs < fs.statSync(path.join(appDir, "pubspec.yaml")).mtimeMs) {
      throw new Error(`${local} нь pubspec.yaml-аас хуучин — эхлээд flutter build apk --release --split-per-abi`);
    }
    await put(key, fs.readFileSync(file), "application/vnd.android.package-archive", {
      ContentDisposition: `attachment; filename="${path.basename(key)}"`,
    });
    manifest.apk[abi] = `${base}/${key}`;
    console.log(`✓ ${key}`);
  }
  // Манифестийг APK-уудын ДАРАА — апп хагас байршуулсан файл руу заахгүй.
  await put("app/version.json", JSON.stringify(manifest), "application/json");
  console.log(`✓ app/version.json  ${version}+${build} (minBuild ${minBuild})`);
})().catch((e) => {
  console.error("НИЙТЛЭЛТ АМЖИЛТГҮЙ:", e.message);
  process.exit(1);
});
