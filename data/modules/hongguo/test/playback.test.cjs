const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "..", "main.js"), "utf8");
const videoId = "7700000000000000001";
const state = { version: 1, deviceId: "123", installId: "456", registered: true, helperDeviceId: "789", helperInstallId: "987", helperRegistered: true, feeds: {} };
const model = { video_duration: 80.5, video_list: [
  { main_url: "https://media.example.invalid/unsupported.mp4", video_meta: { codec_type: "bytevc2", definition: "1080p" } },
  { main_url: "https://media.example.invalid/main.mp4", backup_url: "https://media.example.invalid/backup.mp4", video_meta: { codec_type: "bytevc1", definition: "1080p" } },
] };

function load(response) {
  const cache = new Map();
  const requests = [];
  const host = {
    source: "hongguo",
    utf8Encode: (text) => Uint8Array.from(Buffer.from(text)),
    utf8Decode: (value) => Buffer.from(value).toString("utf8"),
    hexEncode: (value) => Buffer.from(value).toString("hex"),
    hexDecode: (value) => Uint8Array.from(Buffer.from(value, "hex")),
    base64Encode: (value) => Buffer.from(value).toString("base64"),
    base64Decode: (value) => {
      const raw = Buffer.from(value, "base64");
      if (raw.toString("base64").replace(/=+$/, "") !== value.replace(/=+$/, "")) throw new Error("Invalid Base64");
      return Uint8Array.from(raw);
    },
    md5: (value) => Uint8Array.from(crypto.createHash("md5").update(Buffer.from(value)).digest()),
    sha512: (value) => Uint8Array.from(crypto.createHash("sha512").update(Buffer.from(value)).digest()),
    randomBytes: (size) => Uint8Array.from(crypto.randomBytes(size)),
    aesCbcEncrypt: (key, iv, value) => {
      const cipher = crypto.createCipheriv("aes-128-cbc", Buffer.from(key), Buffer.from(iv));
      cipher.setAutoPadding(false);
      return Uint8Array.from(Buffer.concat([cipher.update(Buffer.from(value)), cipher.final()]));
    },
    aesCbcDecrypt: (key, iv, value) => {
      const decipher = crypto.createDecipheriv("aes-128-cbc", Buffer.from(key), Buffer.from(iv));
      decipher.setAutoPadding(false);
      return Uint8Array.from(Buffer.concat([decipher.update(Buffer.from(value)), decipher.final()]));
    },
    parseUrl: (value) => {
      const url = new URL(value);
      return { scheme: url.protocol.slice(0, -1), hostname: url.hostname, userInfo: !!(url.username || url.password) };
    },
    preserveIntegers: (text) => text,
    cacheGet: (key) => cache.get(key) ?? null,
    cacheSet: (key, value) => cache.set(key, value),
    dramaId: (sourceId) => "hongguo:" + sourceId,
    chapterId: (dramaId, videoId) => dramaId + ":" + videoId,
    exclusive: (fn) => fn(),
    retries: () => 1,
    reserve: () => 1,
    fetch: (request) => {
      requests.push(request);
      const answer = typeof response === "function" ? response(request) : response;
      if (answer && typeof answer.status === "number" && "body" in answer) return answer;
      return { status: 200, body: JSON.stringify(answer), headers: {} };
    },
    fetchText: () => { throw new Error("Offline test: webpage fallback"); },
  };
  const context = vm.createContext({ host, module: { exports: {} } });
  vm.runInContext(source + "\nmodule.exports.test = { appMedia, appDetail, fetchAppMedia, fetchTabMedia, fetchPlayerMedia, selectAppMedia, appRequest, paths, webMedia, webPlayback, webDesktopUserAgent, resolveVideoMedia, cencScheme };", context);
  context.module.exports.restoreCatalogState(state);
  return { api: context.module.exports, requests, context, host };
}

for (const nested of [false, true]) {
  test("playback uses the multi_video_model lane and the exact episode in " + (nested ? "1004" : "flat") + " responses", () => {
    const entries = { [videoId]: { video_model: JSON.stringify(model) }, "7700000000000000002": { video_model: {} } };
    const { api, requests } = load({ code: 0, data: nested ? { "1004": entries } : entries });
    const media = api.test.fetchPlayerMedia(videoId, false);
    assert.equal(media.url, "https://media.example.invalid/main.mp4");
    assert.equal(media.quality, 1080);
    assert.equal(media.durationMs, 80500);
    assert.equal(media.variants.length, 2);
    assert.equal(requests.length, 1);
    const request = requests[0];
    const url = new URL(request.url);
    assert.equal(url.hostname, "api5-normal-sinfonlineb.fqnovel.com");
    assert.equal(url.pathname, "/novel/player/multi_video_model/v1/");
    assert.equal(url.searchParams.get("device_id"), state.deviceId);
    assert.equal(url.searchParams.get("iid"), state.installId);
    assert.equal(url.searchParams.get("version_code"), "73932");
    assert.equal(url.searchParams.get("manifest_version_code"), "73932");
    assert.equal(url.searchParams.get("update_version_code"), "73932");
    assert.equal(url.searchParams.get("version_name"), "7.3.9.32");
    assert.equal(url.searchParams.has("ts"), false);
    const payload = JSON.parse(request.body);
    assert.deepEqual(payload.mixed_video_id_map, { "1004": [videoId] });
    assert.equal(payload.dr_scene, "player");
    assert.equal(payload.biz_param.video_platform, 1024);
    assert(request.headers["X-Gorgon"]);
    assert.equal(request.headers["X-Medusa"], "WSQEa3FvS6EV");
    assert.equal(request.headers["X-Helios"], undefined);
    assert.equal(request.headers["X-SS-STUB"], crypto.createHash("md5").update(request.body).digest("hex").toUpperCase());
  });
}

test("playback prefers the signed player request", () => {
  const { api, requests } = load({ code: 0, data: { [videoId]: { video_model: JSON.stringify(model) } } });
  const media = api.test.fetchAppMedia(videoId, false);
  assert.equal(media.url, "https://media.example.invalid/main.mp4");
  assert.equal(media.variants.length, 2);
  assert.equal(requests.length, 1);
  const request = requests[0];
  const url = new URL(request.url);
  assert.equal(request.method, "POST");
  assert.equal(url.hostname, "api5-normal-sinfonlineb.fqnovel.com");
  assert.equal(url.pathname, "/novel/player/multi_video_model/v1/");
  assert(request.headers["X-Gorgon"]);
  assert.equal(request.headers["X-SS-STUB"], crypto.createHash("md5").update(request.body).digest("hex").toUpperCase());
});

test("the video tab is used when the player request has no episode", () => {
  const { api, requests } = load((request) => (request.url.includes("/video_tab/")
    ? { code: 0, data: { video_model_data: { [videoId]: { video_model: model } } } }
    : { code: 0, data: { "7700000000000000002": { video_model: model } } }));
  const media = api.test.fetchAppMedia(videoId, false);
  assert.equal(media.url, "https://media.example.invalid/main.mp4");
  const asked = requests.map((request) => new URL(request.url).pathname);
  assert.equal(asked[asked.length - 1], "/reading/bookapi/video_tab/multi_video_model/v1/");
  assert(asked.length > 1);
  const modelPaths = ["/novel/player/multi_video_model/v1/", "/novel/player/multi_video_model/player/v1", "/novel/player/video_model/v1/"];
  assert(asked.slice(0, -1).every((path) => modelPaths.includes(path)));
});

test("missing requested episode cannot use another episode", () => {
  const { api, requests } = load({ code: 0, data: { "7700000000000000002": { video_model: model } } });
  assert.throws(() => api.test.fetchPlayerMedia(videoId, false), /所请求的分集/);
  assert(requests.length >= 4);
});

test("malformed and rejected models fail explicitly", () => {
  for (const encoded of ["broken", "[]", "42"]) {
    const { api } = load({ code: 0, data: { [videoId]: { video_model: encoded } } });
    assert.throws(() => api.test.fetchPlayerMedia(videoId, false), /格式异常/);
  }
  const { api } = load({ code: 403, data: { [videoId]: { video_model: model } } });
  assert.throws(() => api.test.fetchPlayerMedia(videoId, false), /403/);
});

test("flat pc lanes are read without the nested video metadata", () => {
  const spade = "lbwbxmKBGftitzL5Y7EtzVaKGsVRvC3zZ48b80uNN99klCyJiQ==";
  const { api } = load({ code: 0, data: { video_model_data: { [videoId]: { video_model: {
    video_duration: 58.167, key_seed: "unused",
    video_list: [
      { main_url: "https://media.example.invalid/360.mp4", definition: "360p", codec_type: "bytevc1", vwidth: 360, vheight: 640, encrypt: true, encryption_method: "cenc-aes-ctr", kid: "kid-360", spade_a: spade },
      { main_url: "https://media.example.invalid/720.mp4", definition: "720p", codec_type: "bytevc1", vwidth: 720, vheight: 1280, encrypt: true, encryption_method: "cenc-aes-ctr", kid: "kid-720", spade_a: spade },
    ],
  } } } } });
  const media = api.test.fetchTabMedia(videoId, false, "pc");
  assert.equal(media.url, "https://media.example.invalid/720.mp4");
  assert.equal(media.quality, 720);
  assert.equal(media.durationMs, 58167);
  assert.equal(media.cencKey.length, 24);
  assert.equal(media.variants.length, 2);
});

test("incompatible codecs are retried on the pc lane", () => {
  const vvc = { video_duration: 58.167, video_list: [
    { main_url: "https://media.example.invalid/vvc.mp4", video_meta: { codec_type: "bytevc2", definition: "720p" }, gear_des_key: "1:encrypt|2:bytevc2|4:720p" },
  ] };
  const { api, requests } = load((request) => {
    const url = new URL(request.url);
    if (url.searchParams.get("device_platform") !== "pc") return { code: 0, data: { [videoId]: { video_model: vvc } } };
    return { code: 0, data: { [videoId]: { video_model: { video_duration: 58.167, video_list: [
      { main_url: "https://media.example.invalid/pc720.mp4", definition: "720p", codec_type: "bytevc1", vwidth: 720, vheight: 1280 },
    ] } } } };
  });
  const media = api.test.appMedia(videoId);
  assert.equal(media.url, "https://media.example.invalid/pc720.mp4");
  assert.equal(media.quality, 720);
  const modelPaths = ["/novel/player/multi_video_model/v1/", "/novel/player/multi_video_model/player/v1", "/novel/player/video_model/v1/"];
  const tabPath = "/reading/bookapi/video_tab/multi_video_model/v1/";
  assert(requests.every((request) => [...modelPaths, tabPath].includes(new URL(request.url).pathname)));
  const playerRequests = requests.filter((request) => modelPaths.includes(new URL(request.url).pathname));
  const lanes = playerRequests.map((request) => (new URL(request.url).searchParams.get("device_platform") || "default"));
  assert.equal(lanes[lanes.length - 1], "pc");
  assert(lanes.slice(0, -1).some((lane) => lane === "android"));
  assert.equal(new URL(playerRequests[playerRequests.length - 1].url).searchParams.get("device_id"), state.deviceId);
});

test("the pc lane still falls back to the video tab when the player request fails", () => {
  const vvc = { video_duration: 58.167, video_list: [
    { main_url: "https://media.example.invalid/vvc.mp4", video_meta: { codec_type: "bytevc2", definition: "720p" }, gear_des_key: "1:encrypt|2:bytevc2|4:720p" },
  ] };
  const { api, requests } = load((request) => {
    const url = new URL(request.url);
    if (url.pathname === "/novel/player/multi_video_model/v1/") return { code: 0, data: { "7700000000000000002": { video_model: vvc } } };
    if (url.searchParams.get("device_platform") !== "pc") return { code: 0, data: { video_model_data: { [videoId]: { video_model: vvc } } } };
    return { code: 0, data: { video_model_data: { [videoId]: { video_model: { video_duration: 58.167, video_list: [
      { main_url: "https://media.example.invalid/pctab720.mp4", definition: "720p", codec_type: "bytevc1", vwidth: 720, vheight: 1280 },
    ] } } } } };
  });
  const media = api.test.appMedia(videoId);
  assert.equal(media.url, "https://media.example.invalid/pctab720.mp4");
  const paths = requests.map((request) => new URL(request.url).pathname);
  assert.equal(paths[paths.length - 1], "/reading/bookapi/video_tab/multi_video_model/v1/");
  assert(paths.some((path) => path === "/novel/player/multi_video_model/v1/"));
});

test("a resolved episode is served from the media cache without a second request", () => {
  const { api, requests } = load({ code: 0, data: { [videoId]: { video_model: model } } });
  const first = api.test.appMedia(videoId);
  assert.equal(first.url, "https://media.example.invalid/main.mp4");
  const count = requests.length;
  const second = api.test.appMedia(videoId);
  assert.equal(second.url, first.url);
  assert.equal(requests.length, count);
});

test("one player call prefetches the next episodes from the cached detail", () => {
  const next = ["7700000000000000011", "7700000000000000012"];
  const { api, requests } = load((request) => {
    if (request.url.includes("/video_detail/")) {
      return { code: 0, data: { video_data: {
        series_id: "7700000000000000000", series_name: "合成剧", episode_cnt: 3, video_list: [
          { vid: videoId, vid_index: 1, series_id: "7700000000000000000" },
          { vid: next[0], vid_index: 2, series_id: "7700000000000000000" },
          { vid: next[1], vid_index: 3, series_id: "7700000000000000000" },
        ],
      } } };
    }
    return { code: 0, data: {
      [videoId]: { video_model: model },
      [next[0]]: { video_model: model },
      [next[1]]: { video_model: model },
    } };
  });
  api.test.appDetail("7700000000000000000");
  const media = api.test.resolveVideoMedia({ dramaId: "hongguo:7700000000000000000", chapter: { videoUrl: api.test.cencScheme + videoId } });
  assert.equal(media.url, "https://media.example.invalid/main.mp4");
  const playerCalls = requests.filter((request) => request.url.includes("/multi_video_model/v1/"));
  assert.equal(playerCalls.length, 1);
  assert.deepEqual(JSON.parse(playerCalls[0].body).mixed_video_id_map, { "1004": [videoId, next[0], next[1]] });
  const count = requests.length;
  const prefetched = api.test.resolveVideoMedia({ dramaId: "hongguo:7700000000000000000", chapter: { videoUrl: api.test.cencScheme + next[0] } });
  assert.equal(prefetched.url, "https://media.example.invalid/main.mp4");
  assert.equal(requests.length, count);
});

test("the prefetch batch never exceeds the endpoint limit", () => {
  const total = 40;
  const chapters = [];
  for (let index = 1; index <= total; index++) {
    chapters.push({ vid: "77000000000000" + String(10000 + index), vid_index: index, series_id: "7700000000000000000" });
  }
  const { api, requests } = load((request) => {
    if (request.url.includes("/video_detail/")) {
      return { code: 0, data: { video_data: { series_id: "7700000000000000000", series_name: "合成剧", episode_cnt: total, video_list: chapters } } };
    }
    const payload = JSON.parse(request.body);
    const data = {};
    for (const id of payload.mixed_video_id_map["1004"]) data[id] = { video_model: model };
    return { code: 0, data };
  });
  api.test.appDetail("7700000000000000000");
  api.test.resolveVideoMedia({ dramaId: "hongguo:7700000000000000000", chapter: { videoUrl: api.test.cencScheme + chapters[0].vid } });
  const playerCalls = requests.filter((request) => request.url.includes("/multi_video_model/v1/"));
  assert.equal(playerCalls.length, 1);
  assert.equal(JSON.parse(playerCalls[0].body).mixed_video_id_map["1004"].length, 15);
});

function fallbackFixture() {
  const salt = "4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58";
  const seed = crypto.randomBytes(32);
  const digest = crypto.createHash("sha512").update(Buffer.concat([
    crypto.createHash("sha512").update(seed).digest(),
    Buffer.from(salt, "hex"),
  ])).digest();
  const encode = (address) => {
    const plain = Buffer.from(address, "utf8");
    const pad = 16 - (plain.length % 16);
    const padded = Buffer.concat([plain, Buffer.alloc(pad, pad)]);
    const cipher = crypto.createCipheriv("aes-128-cbc", digest.subarray(0, 16), digest.subarray(16, 32));
    cipher.setAutoPadding(false);
    const ciphertext = Buffer.concat([cipher.update(padded), cipher.final()]);
    return Buffer.concat([Buffer.from([0xa8, 0x00, 0x01, 0x00]), ciphertext]).toString("base64");
  };
  return { seed, encode };
}

function vvcModel() {
  return { video_duration: 61.5, fallback_api: { fallback_api: "https://vas-lf-x.snssdk.com/video/fplay/1/deadbeef/" + videoId + "?aid=8662&codec_type=4&stream_type=encrypt" }, video_list: [
    { main_url: "https://media.example.invalid/vvc.mp4", video_meta: { codec_type: "bytevc2", definition: "720p" }, gear_des_key: "1:encrypt|2:bytevc2|4:720p" },
  ] };
}

test("the fallback play api asks for the faststart ladder instead of the plain master", () => {
  const { seed, encode } = fallbackFixture();
  const vvc = vvcModel();
  const { api, requests } = load((request) => {
    if (new URL(request.url).hostname === "vas-lf-x.snssdk.com") {
      return { video_info: { data: { key_seed: seed.toString("base64"), video_duration: 61.5, video_list: {
        video_1: { main_url: encode("https://media.example.invalid/hevc-720.mp4"), codec_type: "h265", definition: "720p", vwidth: 720, vheight: 1280, encrypt: false, spade_a: "", encryption_method: "" },
        video_2: { main_url: encode("https://media.example.invalid/hevc-1080.mp4"), codec_type: "h265", definition: "1080p", vwidth: 1080, vheight: 1920, encrypt: false, spade_a: "", encryption_method: "" },
      } } } };
    }
    return { code: 0, data: { video_model_data: { [videoId]: { video_model: vvc } } } };
  });
  const media = api.test.appMedia(videoId);
  assert.equal(media.url, "https://media.example.invalid/hevc-1080.mp4");
  assert.equal(media.quality, 1080);
  assert.equal(media.cencKey, undefined);
  assert.equal(media.durationMs, 61500);
  const plays = requests.filter((request) => request.url.includes("/video/fplay/"));
  assert.equal(plays.length, 1);
  const query = new URL(plays[0].url).searchParams;
  assert.deepEqual(query.getAll("codec_type"), ["1"]);
  assert.deepEqual(query.getAll("stream_type"), ["encrypt"]);
});

test("the plain master is only used when no ladder is offered", () => {
  const { seed, encode } = fallbackFixture();
  const vvc = vvcModel();
  const { api, requests } = load((request) => {
    const url = new URL(request.url);
    if (url.hostname === "vas-lf-x.snssdk.com") {
      if (url.searchParams.get("stream_type") !== "plain") {
        // 备用接口的加密通道只给 VVC/H.266，没有可解码的档位。
        return { video_info: { data: { key_seed: seed.toString("base64"), video_duration: 61.5, video_list: {
          video_1: { main_url: encode("https://media.example.invalid/hevc-vvc.mp4"), codec_type: "bytevc2", definition: "1080p", encrypt: true, spade_a: "abc" },
        } } } };
      }
      return { video_info: { data: { key_seed: seed.toString("base64"), video_duration: 61.5, video_list: {
        video_1: { main_url: encode("https://media.example.invalid/master-1080.mp4?token=abc"), codec_type: "h264", definition: "1080p", vwidth: 1080, vheight: 1920, encrypt: false, spade_a: "", encryption_method: "" },
      } } } };
    }
    return { code: 0, data: { video_model_data: { [videoId]: { video_model: vvc } } } };
  });
  const media = api.test.appMedia(videoId);
  assert.equal(media.url, "https://media.example.invalid/master-1080.mp4?token=abc");
  const plays = requests.filter((request) => request.url.includes("/video/fplay/"));
  const plain = plays[plays.length - 1];
  const query = new URL(plain.url).searchParams;
  assert.deepEqual(query.getAll("codec_type"), ["1"]);
  assert.deepEqual(query.getAll("stream_type"), ["plain"]);
  assert(plays.length > 1);
});

test("an empty signature response is retried on the pc lane", () => {
  const { api, requests } = load((request) => {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/service/2/device_register")) return { device_id: "555", install_id: "666" };
    if (url.searchParams.get("device_platform") !== "pc") return { status: 200, body: "", headers: {} };
    return { code: 0, data: { [videoId]: { video_model: model } } };
  });
  const media = api.test.appMedia(videoId);
  assert.equal(media.url, "https://media.example.invalid/main.mp4");
  const lanes = requests.filter((request) => !request.url.includes("/service/2/device_register"));
  assert(lanes.length >= 2);
  assert.equal(new URL(lanes[lanes.length - 1].url).searchParams.get("device_platform"), "pc");
});

test("empty responses across lanes rotate the device before giving up", () => {
  const { api, requests } = load((request) => {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/service/2/device_register")) return { device_id: "555", install_id: "666" };
    if (url.searchParams.get("device_id") === state.deviceId) return { status: 200, body: "", headers: {} };
    return { code: 0, data: { [videoId]: { video_model: model } } };
  });
  const media = api.test.appMedia(videoId);
  assert.equal(media.url, "https://media.example.invalid/main.mp4");
  assert(requests.some((request) => request.url.includes("/service/2/device_register")));
});

test("a blocked version profile falls through to another self-consistent profile", () => {
  const { api, requests, host } = load((request) => {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/service/2/device_register")) return { device_id: "555", install_id: "666" };
    if (url.searchParams.get("version_code") !== "74332") return { status: 200, body: "", headers: {} };
    return { code: 0, data: { [videoId]: { video_model: JSON.stringify(model) } } };
  });
  const media = api.test.appMedia(videoId);
  assert.equal(media.url, "https://media.example.invalid/main.mp4");
  const profiles = requests
    .filter((request) => new URL(request.url).pathname === "/novel/player/multi_video_model/v1/")
    .map((request) => new URL(request.url).searchParams.get("version_code"));
  assert(profiles.includes("74332"));
  assert.equal(host.cacheGet("profile"), "vivo-74332");
  for (const code of profiles) {
    assert(code !== "" && code !== null);
  }
});

test("an all-empty rotation reports the signature block", () => {
  const { api } = load((request) => {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/service/2/device_register")) return { device_id: "555", install_id: "666" };
    return { status: 200, body: "", headers: {} };
  });
  assert.throws(() => api.test.appMedia(videoId), /风控未放行/);
});

test("catalog and detail keep the previous signing and endpoint", () => {
  const { api, requests } = load({ code: 0, data: {} });
  api.test.appRequest("POST", api.test.paths.videoDetail, null, { series_id: "7700000000000000000" });
  assert.equal(new URL(requests[0].url).hostname, "api5-normal-sinfonlineb.fqnovel.com");
  assert(requests[0].headers["X-Gorgon"] && requests[0].headers["X-Argus"] && requests[0].headers["X-Ladon"]);
  assert.equal(requests[0].headers["X-Medusa"], undefined);
});

test("web playback resolves the protected fallback address", () => {
  const mainUrl = "https://v11-hgweb.qznovelvod.com/obj/x?mime_type=video_mp4";
  const { api, requests } = load({
    status: 200,
    body: JSON.stringify({ main_url: mainUrl, url_expire: 1795171132, base_resp: { StatusCode: 0, StatusMessage: "" } }),
    headers: {},
  });
  const media = api.test.webMedia("7700000000000000000", videoId);
  assert.equal(media.url, mainUrl);
  assert.equal(media.referer, "https://hongguoduanju.com/");
  assert.equal(requests.length, 1);
  const request = requests[0];
  assert.equal(request.method, "POST");
  const url = new URL(request.url);
  assert.equal(url.hostname, "hongguoduanju.com");
  assert.equal(url.pathname, "/api/video/protected/fallback-play-info");
  assert.equal(url.searchParams.get("aid"), "8662");
  assert.deepEqual(JSON.parse(request.body), { item_id: videoId });
  assert.equal(request.headers["User-Agent"], api.test.webDesktopUserAgent);
  assert.equal(request.headers["Content-Type"], "application/json");
  assert.equal(request.headers["X-Xs-From-Web"], "1");
  assert.equal(request.headers.Referer, "https://hongguoduanju.com/");
});

test("web playback explains the five episode guest limit", () => {
  const { api, requests } = load({ status: 403, body: JSON.stringify({ error: "public_fallback_unavailable" }), headers: {} });
  assert.throws(() => api.test.webMedia("7700000000000000000", videoId), /前 5 集/);
  assert.equal(requests.length, 1);
});

test("web playback reports a rejected episode without retrying", () => {
  const { api, requests } = load({ status: 400, body: JSON.stringify({ error: "public_fallback_unavailable" }), headers: {} });
  assert.throws(() => api.test.webMedia("7700000000000000000", videoId), /没有为该集开放地址/);
  assert.equal(requests.length, 1);
});

test("web playback falls through to the protected stream and reports encryption", () => {
  const { api, requests } = load((request) => {
    if (request.url.includes("fallback-play-info")) return { status: 500, body: "", headers: {} };
    return {
      status: 200,
      body: JSON.stringify({ play_info: { main_url: "https://v11-hgweb.qznovelvod.com/dash", kid: "6ae6eca9f8818b2038da6ddb0002ebeb", format: "dash" }, base_resp: { StatusCode: 0 } }),
      headers: {},
    };
  });
  assert.throws(() => api.test.webMedia("7700000000000000000", videoId), /加密的 720p/);
  assert.equal(requests.length, 2);
  assert.deepEqual(JSON.parse(requests[1].body), { item_id: videoId, series_id: "7700000000000000000" });
});

test("locked webpage episodes fail through the app api and stay locked", () => {
  const { api, requests } = load((request) => request.url.includes("fallback-play-info")
    ? { status: 403, body: JSON.stringify({ error: "public_fallback_unavailable" }), headers: {} }
    : { status: 200, body: "", headers: {} });
  const task = { dramaId: "hongguo:7700000000000000000", chapter: { videoUrl: api.test.cencScheme + videoId } };
  assert.throws(() => api.test.resolveVideoMedia(task), /前 5 集/);
  assert.equal(requests.filter((request) => request.url.includes("hongguoduanju.com/api/")).length, 1);
  const before = requests.length;
  assert.throws(() => api.test.resolveVideoMedia(task), /不再重试/);
  assert.equal(requests.filter((request) => request.url.includes("hongguoduanju.com/api/")).length, 1);
  // 冷却中的车道直接跳过：第二次取流不会再碰任何播放或列表接口
  const laneHits = requests.slice(before).filter((request) => {
    const pathname = new URL(request.url).pathname;
    return pathname.includes("/novel/player/") || pathname.includes("video_tab");
  });
  assert.equal(laneHits.length, 0);
});

test("v5 digest and carrier match independent synthetic vectors", () => {
  const { context } = load({});
  vm.runInContext("module.exports.vectors = { playbackV5Hash, playbackV5Carrier, signPlaybackV5, playbackV5IV, sm3 };", context);
  const api = context.module.exports.vectors;
  const decode = (text) => Buffer.from(text, "hex");
  const hashes = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "signing-v5-f13.json"), "utf8"));
  assert.equal(hashes.length, 32);
  for (const row of hashes) {
    const result = Buffer.from(api.playbackV5Hash(decode(row.query), decode(row.body), row.ts));
    assert.equal(result.length, 20);
    assert.equal(result.subarray(0, 16).toString("hex"), row.digest);
    assert.equal(result[16] & 0x24, 0x24);
  }
  const carriers = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "signing-v5-carrier.json"), "utf8"));
  assert.equal(carriers.length, 4);
  for (const row of carriers) {
    assert.equal(Buffer.from(api.playbackV5Carrier(decode(row.key), decode(row.iv), decode(row.source), row.ts)).toString("hex"), row.encrypted);
  }
  const values = { aid: "8662", device_id: "123", iid: "456", cdid: "synthetic", version_name: "7.4.3.32", channel: "vivo_8662_64", os_version: "12", device_type: "PGT-AN10" };
  const before = JSON.stringify(values);
  for (let ts = 1800000000; ts < 1800000032; ts++) {
    const body = Buffer.from('{"fixture":true}');
    const signed = api.signPlaybackV5("https://example.invalid/model", values, body, ts * 1000);
    const url = new URL(signed.url);
    const queryHash = crypto.createHash("sm3").update(url.search.slice(1)).digest();
    const bodyHash = crypto.createHash("md5").update(body).digest();
    assert.equal(api.playbackV5IV(queryHash, bodyHash, ts) & 15, 12);
    assert.equal(signed.headers["X-Khronos"], String(ts));
    assert.equal(signed.headers["X-SS-STUB"], bodyHash.toString("hex").toUpperCase());
    assert.equal(url.searchParams.has("ts"), false);
    for (const [key, value] of Object.entries(values)) assert.equal(url.searchParams.get(key), value);
  }
  assert.equal(JSON.stringify(values), before);
});
