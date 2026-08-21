const fs = require("fs");
const path = require("path");

const root = __dirname;
const manifestPath = path.join(root, "careers", "manifest.json");
const errors = [];
let manifest;

try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
} catch (error) {
  console.error(`manifest.json معتبر نیست: ${error.message}`);
  process.exit(1);
}

const requiredArrays = ["phases", "tracks", "chapters", "videos", "sources"];
const ids = new Set();

for (const entry of manifest.careers || []) {
  const filePath = path.resolve(root, entry.file);
  let data;
  try {
    data = JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    errors.push(`${entry.file}: فایل پیدا نشد یا JSON معتبر نیست (${error.message})`);
    continue;
  }

  if (data.schemaVersion !== manifest.schemaVersion) errors.push(`${entry.file}: schemaVersion با manifest یکسان نیست`);
  if (!data.role?.id) errors.push(`${entry.file}: role.id خالی است`);
  if (data.role?.id !== entry.id) errors.push(`${entry.file}: role.id باید برابر ${entry.id} باشد`);
  if (ids.has(entry.id)) errors.push(`${entry.file}: شناسه ${entry.id} در manifest تکراری است`);
  ids.add(entry.id);
  if (!data.guide?.title || !Array.isArray(data.guide?.future)) errors.push(`${entry.file}: بخش guide کامل نیست`);
  if (!Array.isArray(data.flow?.steps)) errors.push(`${entry.file}: flow.steps باید آرایه باشد`);
  if (!data.careerVideo?.sourceUrl) errors.push(`${entry.file}: careerVideo.sourceUrl خالی است`);
  for (const key of requiredArrays) if (!Array.isArray(data[key])) errors.push(`${entry.file}: ${key} باید آرایه باشد`);
}

if (!ids.has("all")) errors.push("مسیر عمومی با id برابر all باید در manifest وجود داشته باشد");

if (errors.length) {
  console.error("اعتبارسنجی ناموفق بود:\n- " + errors.join("\n- "));
  process.exit(1);
}

console.log(`${ids.size} مسیر شغلی معتبر است.`);
