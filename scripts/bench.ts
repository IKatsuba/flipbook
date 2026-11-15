// Runs every render path of the demo three times, each run in a fresh process (so peak memory
// belongs to that run alone), and prints the README tables.
//
//   swift build -c release && deno run --allow-run --allow-read --allow-write scripts/bench.ts

const BIN = ".build/release/flipbook-demo";
const RUNS = 3;

type Result = {
  path: string; mode: string; scale: number; codec: string; speed: boolean; frames: number; width: number; height: number;
  seconds: number; fps: number; cpuMsPerFrame: number; drawMsPerFrame: number; appendMsPerFrame: number;
  finishMs: number; peakRSS: number; peakFootprint: number; bytes: number;
};
type Config = { path: string; mode: string; scale: number; codec: string; speed: boolean; size?: string };

const paths = ["image-renderer", "image-renderer-direct", "core-animation", "metal-composite"];
const configs: Config[] = [];
for (const scale of [1, 2]) {
  for (const speed of [false, true]) {
    for (const path of paths) configs.push({ path, mode: "video", scale, codec: "hevc", speed });
  }
  configs.push({ path: "core-animation", mode: "video", scale, codec: "h264", speed: false });
}
// 1920×1080, the frame size MyGo quotes its number for.
for (const speed of [false, true]) {
  for (const path of ["core-animation", "metal-composite"]) {
    configs.push({ path, mode: "video", scale: 1, codec: "hevc", speed, size: "1920x1080" });
  }
}
for (const scale of [1, 2]) {
  for (const path of paths) configs.push({ path, mode: "draw", scale, codec: "hevc", speed: false });
  configs.push({ path: "core-animation", mode: "encoder", scale, codec: "hevc", speed: false });
  configs.push({ path: "core-animation", mode: "encoder", scale, codec: "hevc", speed: true });
  configs.push({ path: "core-animation", mode: "encoder", scale, codec: "h264", speed: false });
}

async function run(config: Config): Promise<Result> {
  const args = [
    "bench", "--path", config.path, "--mode", config.mode, "--scale", `${config.scale}`,
    "--codec", config.codec, "--speed", config.speed ? "1" : "0", "--size", config.size ?? "1080x1350",
  ];
  const { code, stdout, stderr } = await new Deno.Command(BIN, { args, stdout: "piped", stderr: "piped" }).output();
  if (code !== 0) throw new Error(`${BIN} ${args.join(" ")} failed: ${new TextDecoder().decode(stderr)}`);
  return JSON.parse(new TextDecoder().decode(stdout));
}

const median = (values: number[]) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const spread = (values: number[], digits: number) =>
  `${median(values).toFixed(digits)} (${Math.min(...values).toFixed(digits)}–${Math.max(...values).toFixed(digits)})`;
const pick = (runs: Result[], key: keyof Result) => runs.map((r) => r[key] as number);
const megabytes = (bytes: number) => (bytes / 1024 / 1024).toFixed(1);
const encoder = (config: Config) => config.codec + (config.speed ? ", speed first" : "");

const all: { config: Config; runs: Result[] }[] = [];
for (const config of configs) {
  const runs: Result[] = [];
  for (let i = 0; i < RUNS; i++) runs.push(await run(config));
  all.push({ config, runs });
  console.error(`${config.mode} ${config.path} ${encoder(config)} ${config.size ?? ""} @${config.scale}x: ${spread(pick(runs, "fps"), 1)} fps`);
}

const lines: string[] = [];
lines.push("| Path | Encoder | Pixels | fps, median (min–max) | CPU ms/frame | Draw ms/frame | Encoder wait ms/frame | Peak RSS, MB | Peak footprint, MB | Output, MB |");
lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
for (const { config, runs } of all.filter((entry) => entry.config.mode === "video")) {
  lines.push([
    "", `\`${config.path}\``, encoder(config), `${runs[0].width}×${runs[0].height} (${config.scale}x)`,
    spread(pick(runs, "fps"), 1), median(pick(runs, "cpuMsPerFrame")).toFixed(2), median(pick(runs, "drawMsPerFrame")).toFixed(2),
    median(pick(runs, "appendMsPerFrame")).toFixed(2), megabytes(median(pick(runs, "peakRSS"))),
    megabytes(median(pick(runs, "peakFootprint"))), megabytes(median(pick(runs, "bytes"))), "",
  ].join(" | ").trim());
}
lines.push("");
lines.push("| What runs | Pixels | fps, median (min–max) | CPU ms/frame | Peak RSS, MB | Peak footprint, MB |");
lines.push("| --- | --- | --- | --- | --- | --- |");
for (const { config, runs } of all.filter((entry) => entry.config.mode !== "video")) {
  const what = config.mode === "draw" ? `\`${config.path}\`, drawing only` : `encoder only, ${encoder(config)}`;
  lines.push([
    "", what, `${runs[0].width}×${runs[0].height} (${config.scale}x)`, spread(pick(runs, "fps"), 1),
    median(pick(runs, "cpuMsPerFrame")).toFixed(2), megabytes(median(pick(runs, "peakRSS"))),
    megabytes(median(pick(runs, "peakFootprint"))), "",
  ].join(" | ").trim());
}

await Deno.mkdir("out", { recursive: true });
await Deno.writeTextFile("out/bench.json", JSON.stringify(all, null, 2));
await Deno.writeTextFile("out/bench.md", lines.join("\n") + "\n");
console.log(lines.join("\n"));
