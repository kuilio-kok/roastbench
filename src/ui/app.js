/* 烤机台 v1.2 —— 平滑曲线 / 新玩法 / 拖动 / 紧凑 / 导出图片 */

/* ---------- 图标 ---------- */
const ICON = {
  flame: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"><path d="M12 3c3.6 3.5 6 6.2 6 9.5A6 6 0 0 1 6 12.5C6 9.2 8.4 6.5 12 3Z"/><path d="M12 11c1.7 1.7 2.6 2.9 2.6 4.2a2.6 2.6 0 0 1-5.2 0c0-1.3.9-2.5 2.6-4.2Z"/></svg>',
  cpu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><rect x="6.5" y="6.5" width="11" height="11" rx="2"/><rect x="10" y="10" width="4" height="4" rx=".6"/><path d="M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3"/></svg>',
  gpu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><rect x="3.5" y="6.5" width="17" height="11" rx="2"/><path d="M7.5 10.5h4v3h-4zM12.5 10.5h4v3h-4zM8 20.5h8"/></svg>',
  pulse: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12h4l2.5-6 3.5 12 3-6h7"/></svg>',
  snow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M12 3v18M4.5 7.5l15 9M19.5 7.5l-15 9"/><path d="M12 7.5l2.4-2.4M12 7.5L9.6 5.1M12 16.5l2.4 2.4M12 16.5L9.6 18.9"/></svg>',
  battery: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="8" width="16" height="8" rx="2"/><path d="M20.5 11v2"/><path d="M6 11.5v1M9.5 11.5v1M13 11.5v1"/></svg>',
  mem: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><rect x="3" y="8" width="18" height="8" rx="1.6"/><path d="M7 8v8M11 8v8M15 8v8M3 12h18M8 19h8"/></svg>',
  disk: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><ellipse cx="12" cy="6.5" rx="8" ry="3"/><path d="M4 6.5v11c0 1.7 3.6 3 8 3s8-1.3 8-3v-11"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/></svg>',
  step: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 20h4v-5h4v-5h4V5h6"/></svg>',
  thermo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M9 4a2 2 0 0 1 4 0v8.2a4.5 4.5 0 1 1-4 0V4Z"/><path d="M11 8v6"/><circle cx="11" cy="16.5" r="1.4"/></svg>',
};

const MODES = [
  { id: "max",     icon: "flame",   name: "极限双烤", desc: "CPU + GPU + 内存 + 磁盘全压" },
  { id: "cpu",     icon: "cpu",     name: "CPU 单烤", desc: "只压处理器，看散热上限" },
  { id: "gpu",     icon: "gpu",     name: "GPU 单烤", desc: "Metal 算力拉满" },
  { id: "mem",     icon: "mem",     name: "内存单烤", desc: "只打带宽，几乎不升温" },
  { id: "io",      icon: "disk",    name: "磁盘单烤", desc: "反复读写，看 SSD 表现" },
  { id: "pulse",   icon: "pulse",   name: "温度探底", desc: "烤 45 秒歇 15 秒，逼近温度墙" },
  { id: "step",    icon: "step",    name: "阶梯升载", desc: "每 20 秒加一档，找功耗拐点" },
  { id: "thermo",  icon: "thermo",  name: "恒温模式", desc: "自动调节负载，稳住目标温度" },
  { id: "passive", icon: "snow",    name: "凉拌模式", desc: "只开一半核心，无风扇机型用" },
  { id: "battery", icon: "battery", name: "电池降频", desc: "不插电能撑到多少瓦" },
];

/* ---------- 多语言 ---------- */
let lang = "zh";
const I18N_EN = {
  // 模式
  "极限双烤": "Extreme Burn", "CPU + GPU + 内存 + 磁盘全压": "CPU + GPU + RAM + disk at full load",
  "CPU 单烤": "CPU Burn", "只压处理器，看散热上限": "CPU only — find the thermal ceiling",
  "GPU 单烤": "GPU Burn", "Metal 算力拉满": "Max out Metal compute",
  "内存单烤": "Memory Burn", "只打带宽，几乎不升温": "Bandwidth only, barely heats up",
  "磁盘单烤": "Disk Burn", "反复读写，看 SSD 表现": "Repeated I/O — test the SSD",
  "温度探底": "Temp Probing", "烤 45 秒歇 15 秒，逼近温度墙": "45s on / 15s off, probe the thermal wall",
  "阶梯升载": "Step Load", "每 20 秒加一档，找功耗拐点": "+1 stage / 20s, find the power knee",
  "恒温模式": "Thermostat", "自动调节负载，稳住目标温度": "Closed-loop load, hold the target temp",
  "凉拌模式": "Passive Cool", "只开一半核心，无风扇机型用": "Half cores — for fanless machines",
  "电池降频": "Battery Test", "不插电能撑到多少瓦": "See how many watts on battery",
  // 标题 / 按钮
  "实时概况": "Live Overview", "压力模式": "Stress Modes",
  "开始烤机": "Start Burn", "停止烤机": "Stop Burn", "就绪": "Ready",
  "温度曲线": "Temperature", "功耗曲线": "Power", "风扇与频率": "Fans & Frequency",
  "设置": "Settings", "完成": "Done", "导出": "Export",
  "本轮峰值": "This Run", "本机纪录": "History", "时长": "Duration", "目标温度": "Target Temp",
  "手动": "Manual", "推荐": "Recommended",
  // 设备卡
  "芯片 · 核心": "Chip · Cores", "图形": "Graphics", "内存": "Memory", "磁盘": "Disk",
  "散热": "Cooling", "供电": "Power Source",
  "外接电源": "AC Power", "电池供电": "On Battery",
  // 指标
  "CPU温度": "CPU Temp", "GPU温度": "GPU Temp", "芯片功耗": "Chip Power", "CPU功耗": "CPU Power",
  "GPU功耗": "GPU Power", "整机功耗": "System Power", "风扇": "Fan", "P核频率": "P-Core Freq",
  "GPU频率": "GPU Freq", "E核频率": "E-Core Freq", "CPU占用": "CPU Usage", "GPU占用": "GPU Usage",
  "内存占用": "Memory Usage", "内存已用": "RAM Used", "磁盘读": "Disk Read", "磁盘写": "Disk Write",
  // 设置分节
  "外观": "Appearance", "安全": "Safety", "采样": "Sampling", "压测": "Burn", "通用": "General", "关于": "About",
  "硬件详情": "Hardware", "传感器面板": "Sensors",
};
function t(text) { return lang === "en" ? (I18N_EN[text] || text) : text; }
function resolveLang(s) {
  if (s === "en") return "en";
  if (s === "zh") return "zh";
  return navigator.language && navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
}
function applyLang() {
  document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
  document.querySelectorAll("[data-i18n-t]").forEach((el) => { el.title = t(el.dataset.i18nT); });
  $("btnStart").textContent = running ? t("停止烤机") : t("开始烤机");
  if (!running) $("runState").textContent = t("就绪");
  renderModes();
  refreshChartTitles();
}
function refreshChartTitles() {
  const map = { cvTemp: "temp", cvPower: "power", cvFan: "fan" };
  charts.forEach((ch) => {
    const nm = map[ch.cv.id];
    const el = document.querySelector(`[data-chart-title="${nm}"]`);
    if (el) el.textContent = t(CHART_DEFS[nm].title);
  });
}

/* ---------- 状态 ---------- */
let info = null, settings = null, mode = "max", recMode = "max";
let running = false, startedAt = 0, battAtStart = null;
let duration = 0, targetTemp = 95;
let hist = [], smHist = [], runS = [], longHist = [];
let charts = [];
let intervalMs = 250, windowSec = 60, cap = 240;
let lastTickAt = 0, rafId = null, timerId = null;
let C = {};
const SMOOTH_KEYS = ["ct", "gt", "cw", "gw", "aw", "sw", "fan", "pf", "ef", "gf", "cu", "gu", "mu", "ru", "su", "dr", "dw"];

const $ = (id) => document.getElementById(id);
const toastBox = $("toasts");

/* ---------- 桥 ---------- */
let _seq = 0;
const _pending = new Map();
function call(op, data = {}) {
  return new Promise((res) => {
    const id = ++_seq;
    _pending.set(id, res);
    window.webkit.messageHandlers.api.postMessage(Object.assign({ op, id }, data));
  });
}
window.__reply = (id, payload) => {
  const r = _pending.get(id);
  if (r) { _pending.delete(id); r(payload); }
};

/* ---------- 指标字典 / 图表定义 ---------- */
const METRICS = {
  ct: { n: "CPU温度", u: "°C", c: "c-cpu",  f: (v) => v.toFixed(0) + "°C" },
  gt: { n: "GPU温度", u: "°C", c: "c-gpu",  f: (v) => v.toFixed(0) + "°C" },
  aw: { n: "芯片功耗", u: "W", c: "c-all",  f: (v) => v.toFixed(1) + "W" },
  cw: { n: "CPU功耗", u: "W", c: "c-cpuw", f: (v) => v.toFixed(1) + "W" },
  gw: { n: "GPU功耗", u: "W", c: "c-gpuw", f: (v) => v.toFixed(1) + "W" },
  sw: { n: "整机功耗", u: "W", c: "c-gpu",  f: (v) => v.toFixed(0) + "W" },
  fan:{ n: "风扇",     u: "RPM", c: "c-fan", f: (v) => Math.round(v) },
  pf: { n: "P核频率",  u: "MHz", c: "c-freq", f: (v) => Math.round(v) + "MHz", dash: true },
  gf: { n: "GPU频率",  u: "MHz", c: "c-freq", f: (v) => Math.round(v) + "MHz", dash: true },
  ef: { n: "E核频率",  u: "MHz", c: "c-freq", f: (v) => Math.round(v) + "MHz", dash: true },
  cu: { n: "CPU占用",  u: "%",  c: "c-cpu",  f: (v) => v.toFixed(0) + "%" },
  gu: { n: "GPU占用",  u: "%",  c: "c-gpuw", f: (v) => v.toFixed(0) + "%" },
  mu: { n: "内存占用", u: "%", c: "c-gpu",  f: (v) => v.toFixed(0) + "%" },
  ru: { n: "内存已用", u: "GB", c: "c-gpuw", f: (v) => v.toFixed(1) + "GB" },
  su: { n: "Swap",     u: "GB", c: "c-gpu",  f: (v) => v.toFixed(2) + "GB" },
  dr: { n: "磁盘读",   u: "MB/s", c: "c-all", f: (v) => v.toFixed(1) },
  dw: { n: "磁盘写",   u: "MB/s", c: "c-cpuw", f: (v) => v.toFixed(1) },
};
const CHART_DEFS = {
  temp:  { title: "温度曲线",   keys: ["ct", "gt"], fixed: [0, 115], snap: 5 },
  power: { title: "功耗曲线",   keys: ["aw", "cw", "gw"], fixed: [0, 60], snap: 5 },
  fan:   { title: "风扇与频率", keys: ["fan", "pf"], fixed: [0, 6500], snap: 500 },
};

/* ---------- 个性化配色 ---------- */
const ACCENTS = ["", "#007AFF", "#0A84FF", "#5856D6", "#34C759", "#FF9F0A", "#FF6A35", "#FF375F", "#AF52DE", "#00C7BE"];
const CHART_THEMES = {
  apple: { name: "默认", c_cpu: "#FF9500", c_gpu: "#FF453A", c_all: "#0A84FF", c_cpuw: "#5E5CE6", c_gpuw: "#BF5AF2", c_fan: "#32D74B", c_freq: "#64D2FF" },
  warm:  { name: "暖阳", c_cpu: "#FF7A45", c_gpu: "#FF453A", c_all: "#FF9F0A", c_cpuw: "#FF6482", c_gpuw: "#FFA940", c_fan: "#7AC70C", c_freq: "#FFD60A" },
  ocean: { name: "海洋", c_cpu: "#00C7BE", c_gpu: "#0A84FF", c_all: "#5AC8FA", c_cpuw: "#5856D6", c_gpuw: "#AF52DE", c_fan: "#32D74B", c_freq: "#64D2FF" },
  neon:  { name: "霓虹", c_cpu: "#FF2D55", c_gpu: "#FF9500", c_all: "#00E5FF", c_cpuw: "#7B61FF", c_gpuw: "#FF375F", c_fan: "#30D158", c_freq: "#FFD60A" },
  mono:  { name: "石墨", c_cpu: "#8E8E93", c_gpu: "#D1D1D6", c_all: "#5E5CE6", c_cpuw: "#48484A", c_gpuw: "#C7C7CC", c_fan: "#3A3A3C", c_freq: "#8E8E93" },
};
const WALLPAPERS = [
  { id: "none", name: "默认" },
  { id: "aurora", name: "极光" },
  { id: "sunset", name: "落日" },
  { id: "night", name: "夜航" },
  { id: "mono", name: "素灰" },
  { id: "custom", name: "我的图片" },
];
function hexA(hex, a) {
  const n = (hex || "").replace("#", "");
  if (n.length < 6) return "rgba(0,0,0,0.1)";
  const r = parseInt(n.substr(0, 2), 16), g = parseInt(n.substr(2, 2), 16), b = parseInt(n.substr(4, 2), 16);
  return "rgba(" + r + "," + g + "," + b + "," + a + ")";
}
function shade(hex, pct) {
  const n = hex.replace("#", "");
  const f = (i) => Math.max(0, Math.min(255, parseInt(n.substr(i, 2), 16) + pct));
  return "#" + [f(0), f(2), f(4)].map((v) => v.toString(16).padStart(2, "0")).join("");
}

/* ---------- 主题 ---------- */
function refreshColors() {
  const cs = getComputedStyle(document.documentElement);
  const ct = settings && CHART_THEMES[settings.chartTheme] ? CHART_THEMES[settings.chartTheme] : null;
  const cc = settings && settings.customColors ? settings.customColors : {};
  ["c-cpu", "c-gpu", "c-all", "c-cpuw", "c-gpuw", "c-fan", "c-freq"].forEach((k) => {
    C[k] = cc[k] || (ct ? ct[k] : (cs.getPropertyValue("--" + k).trim() || "#888"));
  });
  C.text = cs.getPropertyValue("--text").trim();
  C.text2 = cs.getPropertyValue("--text-2").trim();
  C.text3 = cs.getPropertyValue("--text-3").trim();
  C.grid = cs.getPropertyValue("--grid").trim();
  C.tooltip = cs.getPropertyValue("--tooltip").trim();
  C.hair = cs.getPropertyValue("--hair-strong").trim();
}
window.__theme = (dark) => {
  document.documentElement.dataset.theme = dark ? "dark" : "light";
  refreshColors();
  redrawAll();
};

/* ---------- 平滑数据流：居中移动平均，曲线连续，读数仍用原始值 ---------- */
const SMOOTH_WIN = 7;   // 单侧 7 点 → 共 15 点 ≈ 3.7 秒
function rebuildSmoothed() {
  const n = hist.length, keys = SMOOTH_KEYS;
  smHist = new Array(n);
  for (let i = 0; i < n; i++) {
    const s = { t: hist[i].t };
    for (const k of keys) {
      let sum = 0, cnt = 0;
      const a = Math.max(0, i - SMOOTH_WIN), b = Math.min(n - 1, i + SMOOTH_WIN);
      for (let j = a; j <= b; j++) { sum += hist[j][k]; cnt++; }
      s[k] = sum / cnt;
    }
    smHist[i] = s;
  }
}
function pushSample(d) {
  // 派生字段：内存占用率
  if (d.rt > 0) d.mu = (d.ru / d.rt) * 100; else d.mu = 0;
  hist.push(d);
  if (hist.length > cap) hist.shift();
  // 全量历史（供全屏查看，上限约 50 分钟）
  longHist.push(d);
  if (longHist.length > 12000) longHist.shift();
  rebuildSmoothed();
}

/* ---------- 图表 ---------- */
function damp(cur, target, rate) {
  return cur == null ? target : cur + (target - cur) * rate;
}

class Chart {
  constructor(canvasId, def, opts = {}) {
    this.cv = $(canvasId);
    this.ctx = this.cv.getContext("2d");
    this.def = def;
    this.keys = def.keys.slice();
    this.series = [];
    this.opts = Object.assign({ rows: 4, padL: 48, fixed: def.fixed || [0, 100], warmup: 16, snap: def.snap }, opts);
    this.buildSeries();
    this.hoverX = null;
    this.curTop = null; this.curBot = null;
    this.dashTop = null; this.dashBot = null;
    this._main = [null, null];
    this._dash = [null, null];
    this.step = null; this.dashStep = null;
    this.bindHover();
  }

  buildSeries() {
    this.series = this.keys.map((k) => {
      const m = METRICS[k];
      return { key: k, name: m.n, unit: m.u, fmt: m.f, dashed: !!m.dash, color: () => C[m.c] };
    });
  }
  setKeys(keys) { this.keys = keys.slice(); this.buildSeries(); this.step = null; this.dashStep = null; }

  bindHover() {
    this.cv.addEventListener("mousemove", (e) => {
      const r = this.cv.getBoundingClientRect();
      this.hoverX = e.clientX - r.left;
      ensureLoop();
    });
    this.cv.addEventListener("mouseleave", () => { this.hoverX = null; ensureLoop(); });
  }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const r = this.cv.getBoundingClientRect();
    const w = Math.max(1, Math.round(r.width)), h = Math.max(1, Math.round(r.height));
    if (this.cv.width !== w * dpr || this.cv.height !== h * dpr) {
      this.cv.width = w * dpr; this.cv.height = h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    this.w = w; this.h = h;
  }

  // nice ticks：轴刻度永远是 1/2/5 序列，数据小幅波动不会改变轴
  niceRange(data, keys) {
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < data.length; i++) {
      for (const k of keys) {
        const v = data[i][k];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (!isFinite(lo)) { lo = 0; hi = 1; }
    if (hi - lo < 1e-6) { lo = Math.max(0, lo - 2); hi = lo + 4; }
    const pad = (hi - lo) * 0.12;
    const lo2 = Math.max(0, lo - pad), hi2 = hi + pad;
    const rough = (hi2 - lo2) / 4;
    const mag = Math.pow(10, Math.floor(Math.log10(rough)));
    const norm = rough / mag;
    const step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
    const bot = Math.floor(lo2 / step) * step;
    let top = bot, cells = 0;
    do { top += step; cells++; } while (top < hi2 && cells < 8);
    return [top, bot, step];
  }

  // 只在跨过一整格时才更新轴，避免逐像素漂移造成的抽搐
  settle(slot, tTop, tBot, snap) {
    if (slot[0] == null) { slot[0] = tTop; slot[1] = tBot; return; }
    const s = snap || Math.max((tTop - tBot) / this.opts.rows, 1);
    if (Math.abs(tTop - slot[0]) > s * 0.5 || Math.abs(tBot - slot[1]) > s * 0.5) {
      slot[0] = tTop; slot[1] = tBot;
    }
  }

  draw(phase) {
    this.resize();
    const g = this.ctx, W = this.w, H = this.h;
    if (W < 20 || H < 20) return;
    const padL = this.opts.padL, padR = 14, padT = 12, padB = 20;
    const pw = W - padL - padR, ph = H - padT - padB;
    g.clearRect(0, 0, W, H);
    if (pw <= 4 || ph <= 4) return;

    const data = smHist, raw = hist, n = data.length;
    if (n < 2) {
      g.fillStyle = C.text3; g.font = "11px -apple-system,sans-serif"; g.textAlign = "center";
      g.fillText("等待数据…", W / 2, H / 2);
      return;
    }

    // 纵轴：预热锁固定量程，之后 nice ticks；数据没逼近边界就不动轴
    const mainKeys = this.series.filter((s) => !s.dashed).map((s) => s.key);
    if (n < this.opts.warmup) {
      this.curTop = this.opts.fixed[1]; this.curBot = this.opts.fixed[0];
      this.step = (this.opts.fixed[1] - this.opts.fixed[0]) / 4;
    } else {
      const [tTop, tBot, tStep] = this.niceRange(data, mainKeys);
      if (this.curTop == null || tTop > this.curTop || tBot < this.curBot ||
          tTop - tBot < (this.curTop - this.curBot) * 0.45) {
        this.curTop = tTop; this.curBot = tBot; this.step = tStep;
      }
      this.step = this.step || tStep;
    }

    const step = this.step || (this.curTop - this.curBot) / 4 || 1;
    const fmtV = (v) => v >= 1000 ? (v / 1000).toFixed(v % 1000 ? 1 : 0) + "k" : (Number.isInteger(v) ? v : v.toFixed(1));
    // 主网格线 + 左端刻度
    g.lineWidth = 1;
    g.font = "10px ui-monospace,SF Mono,Menlo,monospace";
    g.textAlign = "right";
    for (let v = this.curBot; v <= this.curTop + 1e-6; v += step) {
      const y = Math.round(padT + ph - ((v - this.curBot) / (this.curTop - this.curBot || 1)) * ph) + .5;
      g.strokeStyle = C.grid;
      g.beginPath(); g.moveTo(padL, y); g.lineTo(W - padR, y); g.stroke();
      g.strokeStyle = C.text3;
      g.beginPath(); g.moveTo(padL - 4, y); g.lineTo(padL, y); g.stroke();
      g.fillStyle = C.text3;
      g.fillText(fmtV(v), padL - 9, y + 3.5);
    }
    // Y 轴单位
    const unit = this.series[0] ? this.series[0].unit : "";
    g.fillStyle = C.text3; g.textAlign = "right";
    g.fillText(unit, padL - 9, padT - 2);
    // 底部时间轴
    g.textAlign = "center"; g.font = "9.5px ui-monospace,SF Mono,Menlo,monospace";
    const ticks = 5;
    for (let i = 0; i < ticks; i++) {
      const frac = i / (ticks - 1);
      const x = padL + pw * frac;
      const sec = -Math.round(windowSec * (1 - frac));
      g.fillText(fmtDur(sec), x, H - 5);
    }

    const pxPer = pw / (cap - 1);
    this.series.forEach((s) => {
      if (!s.dashed) this.stroke(s, data, n, phase, padL, padT, pw, ph, pxPer, this.curTop, this.curBot);
    });

    // 虚线副轴（频率），同样 nice
    const dash = this.series.find((s) => s.dashed);
    if (dash) {
      if (n < this.opts.warmup) {
        this.dashTop = this.opts.fixed[1]; this.dashBot = this.opts.fixed[0]; this.dashStep = this.opts.fixed[1] / 4;
      } else {
        const [dt, db, ds] = this.niceRange(data, [dash.key]);
        if (this.dashTop == null || dt > this.dashTop || db < this.dashBot ||
            dt - db < (this.dashTop - this.dashBot) * 0.45) {
          this.dashTop = dt; this.dashBot = db; this.dashStep = ds;
        }
        this.dashStep = this.dashStep || ds;
      }
      this.stroke(dash, data, n, phase, padL, padT, pw, ph, pxPer, this.dashTop, this.dashBot);
    }

    // 峰值参考线（原始值）
    if (settings && settings.showPeak && running && runS.length > 5) {
      const pk = runS.reduce((a, x) => Math.max(a, x[mainKeys[0]]), 0);
      const y = padT + ph - ((pk - this.curBot) / (this.curTop - this.curBot || 1)) * ph;
      if (y > padT && y < padT + ph) {
        g.save();
        g.setLineDash([5, 4]); g.strokeStyle = C.text3; g.lineWidth = 1;
        g.beginPath(); g.moveTo(padL, y); g.lineTo(W - padR, y); g.stroke();
        g.setLineDash([]);
        g.fillStyle = C.text2; g.font = "10px -apple-system,sans-serif"; g.textAlign = "left";
        g.fillText("本轮峰值 " + this.series[0].fmt(pk), padL + 4, y - 5);
        g.restore();
      }
    }

    if (this.hoverX != null && this.hoverX >= padL && this.hoverX <= W - padR) {
      this.drawHover(g, raw, n, phase, padL, padT, pw, ph, pxPer, W, padR);
    }
  }

  drawHover(g, raw, n, phase, padL, padT, pw, ph, pxPer, W, padR) {
    const idx = Math.max(0, Math.min(n - 1, Math.round((this.hoverX - padL) / pxPer + phase)));
    const d = raw[idx];
    if (!d) return;
    const x = padL + (idx - phase) * pxPer;
    g.save();
    g.strokeStyle = C.hair; g.lineWidth = 1;
    g.beginPath(); g.moveTo(x, padT); g.lineTo(x, padT + ph); g.stroke();

    this.series.forEach((s) => {
      const top = s.dashed ? this.dashTop : this.curTop;
      const bot = s.dashed ? this.dashBot : this.curBot;
      const y = padT + ph - ((d[s.key] - bot) / (top - bot || 1)) * ph;
      g.beginPath(); g.arc(x, y, 3, 0, Math.PI * 2);
      g.fillStyle = s.color(); g.fill();
      g.strokeStyle = C.tooltip; g.lineWidth = 1.5; g.stroke();
    });

    const lines = this.series.map((s) => s.name + " " + s.fmt(d[s.key]));
    const ago = Math.max(0, Math.round(Date.now() / 1000 - d.t));
    g.font = "11px -apple-system,sans-serif";
    let bw = 0;
    lines.forEach((t) => { bw = Math.max(bw, g.measureText(t).width + 56); });
    bw = Math.max(bw, g.measureText(ago + " 秒前").width + 20);
    const bh = (lines.length + 1) * 16 + 8;
    let bx = x + 10, by = padT + 4;
    if (bx + bw > W - padR) bx = x - bw - 10;
    g.fillStyle = C.tooltip; g.strokeStyle = C.hair; g.lineWidth = 1;
    g.beginPath();
    if (g.roundRect) g.roundRect(bx, by, bw, bh, 9); else g.rect(bx, by, bw, bh);
    g.fill(); g.stroke();
    g.textAlign = "left"; g.fillStyle = C.text3;
    g.fillText(ago + " 秒前", bx + 10, by + 19);
    this.series.forEach((s, i) => {
      const yy = by + 19 + (i + 1) * 16;
      g.fillStyle = s.color();
      g.beginPath(); g.arc(bx + 13, yy - 4, 2.5, 0, Math.PI * 2); g.fill();
      g.fillStyle = C.text; g.fillText(s.name, bx + 21, yy);
      g.fillStyle = C.text2; g.textAlign = "right";
      g.fillText(s.fmt(d[s.key]), bx + bw - 10, yy);
      g.textAlign = "left";
    });
    g.restore();
  }

  stroke(s, data, n, phase, padL, padT, pw, ph, pxPer, top, bot) {
    const g = this.ctx;
    const span = top - bot || 1;
    const X = (i) => padL + (i - phase) * pxPer;
    const Y = (v) => padT + ph - ((v - bot) / span) * ph;
    const col = s.color();

    g.save();
    g.beginPath(); g.rect(padL, 0, pw, this.h); g.clip();

    const pts = [];
    for (let i = 0; i < n; i++) pts.push([X(i), Y(data[i][s.key])]);
    const trace = () => smoothPath(g, pts);

    if (s.dashed) {
      trace();
      g.setLineDash([4, 3]); g.strokeStyle = col; g.lineWidth = 1.1; g.stroke();
    } else {
      // 面积填充（设置可关）
      if ((settings && settings.chartFill) !== false) {
        trace();
        g.lineTo(X(n - 1), padT + ph); g.lineTo(X(0), padT + ph); g.closePath();
        const grad = g.createLinearGradient(0, padT, 0, padT + ph);
        grad.addColorStop(0, hexA(col, .22)); grad.addColorStop(1, hexA(col, 0));
        g.fillStyle = grad; g.fill();
      }

      trace();
      g.strokeStyle = col;
      g.lineWidth = (settings && settings.chartLine) || 1.6;
      g.lineJoin = "round"; g.lineCap = "round";
      g.stroke();
      g.beginPath(); g.arc(X(n - 1), Y(data[n - 1][s.key]), 2.4, 0, Math.PI * 2);
      g.fillStyle = col; g.fill();
    }
    g.restore();
  }
}

function fmtDur(sec) {
  if (sec === 0) return "现在";
  const a = Math.abs(sec);
  if (a < 60) return "-" + a + "s";
  return "-" + Math.floor(a / 60) + ":" + String(a % 60).padStart(2, "0");
}
// Catmull-Rom 转贝塞尔，曲线自然圆滑，不再锯齿
function smoothPath(g, pts) {
  g.beginPath();
  if (pts.length < 3) {
    pts.forEach((p, i) => (i === 0 ? g.moveTo(p[0], p[1]) : g.lineTo(p[0], p[1])));
    return;
  }
  g.moveTo(pts[0][0], pts[0][1]);
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)];
    const c1x = p1[0] + (p2[0] - p0[0]) / 6, c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6, c2y = p2[1] - (p3[1] - p1[1]) / 6;
    g.bezierCurveTo(c1x, c1y, c2x, c2y, p2[0], p2[1]);
  }
}

function drawSpark(id, key, colorFn) {
  const cv = $(id);
  if (!cv) return;
  const g = cv.getContext("2d");
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const r = cv.getBoundingClientRect();
  const w = Math.max(1, Math.round(r.width)), h = Math.max(1, Math.round(r.height));
  if (w < 4) return;
  if (cv.width !== w * dpr) { cv.width = w * dpr; cv.height = h * dpr; g.setTransform(dpr, 0, 0, dpr, 0, 0); }
  g.clearRect(0, 0, w, h);
  const d = smHist.slice(-90), n = d.length;
  if (n < 3) return;
  let lo = Infinity, hi = -Infinity;
  d.forEach((x) => { const v = x[key]; if (v < lo) lo = v; if (v > hi) hi = v; });
  const span = hi - lo || 1;
  const X = (i) => (w * i) / (n - 1);
  const Y = (v) => h - 2 - ((v - lo) / span) * (h - 5);
  const col = colorFn();
  const pts = d.map((x, i) => [X(i), Y(x[key])]);
  smoothPath(g, pts);
  g.lineTo(w, h); g.lineTo(0, h); g.closePath();
  const grad = g.createLinearGradient(0, 0, 0, h);
  grad.addColorStop(0, hexA(col, .13)); grad.addColorStop(1, hexA(col, 0));
  g.fillStyle = grad; g.fill();
  smoothPath(g, pts);
  g.strokeStyle = col; g.lineWidth = 1.3; g.stroke();
}

/* ---------- 渲染循环 ---------- */
function ensureLoop() { if (rafId === null) rafId = requestAnimationFrame(frame); }
function frame(t) {
  const idle = t - lastTickAt;
  if (idle > 2400) { rafId = null; redrawAll(); return; }
  const phase = Math.min(idle / intervalMs, 1);
  charts.forEach((c) => c.draw(phase));
  drawSpark("sp1", "ct", () => C["c-cpu"]);
  drawSpark("sp2", "gt", () => C["c-gpu"]);
  drawSpark("sp3", "aw", () => C["c-all"]);
  drawSpark("sp4", "fan", () => C["c-fan"]);
  $("beat").classList.toggle("on", idle < intervalMs * 2.2);
  rafId = requestAnimationFrame(frame);
}
function redrawAll() {
  const phase = Math.min((performance.now() - lastTickAt) / intervalMs, 1);
  charts.forEach((c) => c.draw(phase));
  drawSpark("sp1", "ct", () => C["c-cpu"]);
  drawSpark("sp2", "gt", () => C["c-gpu"]);
  drawSpark("sp3", "aw", () => C["c-all"]);
  drawSpark("sp4", "fan", () => C["c-fan"]);
}

/* ---------- 界面 ---------- */
function renderModes() {
  $("modeList").innerHTML = MODES.map((m) => `
    <div class="mode ${m.id === mode ? "sel" : ""}" data-id="${m.id}">
      <span class="mk">${ICON[m.icon]}</span>
      <span>
        <span class="mt">${t(m.name)}</span>
        <span class="md">${t(m.desc)}</span>
        ${recMode === m.id ? '<span class="rec">' + t("推荐") + '</span>' : ""}
      </span>
    </div>`).join("");
  document.querySelectorAll(".mode").forEach((el) => {
    el.onclick = () => {
      if (running) return;
      mode = el.dataset.id;
      $("targetRow").hidden = mode !== "thermo";
      renderModes();
    };
  });
}

function renderInfo(i) {
  info = i;
  $("devName").textContent = i.display_name || i.model_name;
  $("devSub").textContent = `${i.model_id} · macOS ${i.macos}`;
  $("spChip").textContent = `${i.chip} · ${i.pcores && i.ecores ? i.ncpu + " 核（" + i.pcores + "P+" + i.ecores + "E）" : i.ncpu + " 核"}`;
  $("spGpu").textContent = i.gpu || "—";
  $("spMem").textContent = `${i.memory_gb} GB`;
  $("spFan").textContent = i.fanless === null ? "判定中" : (i.fanless ? "被动散热" : "主动风扇");
  setPowerUI(i.power);
  $("aboutChip").textContent = i.chip;
  recMode = recommend(i);
  $("recHint").textContent = hintFor(i);
  $("setThreads").max = String(i.ncpu || 16);
  renderModes();
}

function setPowerUI(src, pct) {
  const el = $("spPower");
  const batt = src === "battery";
  el.textContent = batt ? (pct != null ? `电池 ${pct}%` : "电池供电") : "外接电源";
  el.classList.toggle("warn", batt);
}

const setText = (id, v) => { const el = $(id); if (el.textContent !== String(v)) el.textContent = v; };

function updateText(d) {
  window._last = d;
  setText("hCpuTemp", d.ct.toFixed(0));
  setText("hGpuTemp", d.gt.toFixed(0));
  setText("hAllW", d.aw.toFixed(1));
  setText("hFan", d.fn === 0 ? "无" : (d.fan > 0 ? Math.round(d.fan).toLocaleString() : "停转"));
  if (d.rt > 0) $("spMem").textContent = `${d.ru.toFixed(1)} / ${d.rt.toFixed(0)} GB · ${d.mu.toFixed(0)}%`;
  if (d.dt > 0) $("spDisk").textContent = `可用 ${d.df.toFixed(0)} / ${d.dt.toFixed(0)} GB · 读 ${d.dr.toFixed(0)} · 写 ${d.dw.toFixed(0)} MB/s`;
  charts.forEach((ch) => {
    if (!ch.legendEl) return;
    ch.legendEl.innerHTML = ch.series.map((sr) =>
      `<span><i style="background:${sr.color()}${sr.dashed ? ';border-top:2px dashed ' + sr.color() : ''}"></i>${sr.name} <b>${sr.fmt(d[sr.key])}</b></span>`).join("");
  });
  if (running) updatePeaks();
}

function updatePeaks() {
  const mx = (k) => runS.reduce((a, x) => Math.max(a, x[k]), 0);
  const mn = (k) => runS.reduce((a, x) => Math.min(a, x[k]), Infinity);
  const f = mx("fan"), hasFans = runS.some((x) => x.fn > 0);
  setText("pkCpu", mx("ct").toFixed(0) + "°C");
  setText("pkGpu", mx("gt").toFixed(0) + "°C");
  setText("pkAll", mx("aw").toFixed(1) + " W");
  setText("pkSys", mx("sw").toFixed(0) + " W");
  setText("pkFan", !hasFans ? "无风扇" : (f > 0 ? Math.round(f) + " RPM" : "停转"));
  const lf = mn("pf");
  setText("pkFreq", isFinite(lf) ? Math.round(lf) + " MHz" : "—");
  setText("runNote", MODES.find((m) => m.id === mode).name + " · 进行中");
}

function tickTimer() {
  const s = Math.floor((Date.now() - startedAt) / 1000);
  setText("timer", String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0"));
  if (duration > 0) {
    const p = Math.min(100, (s / duration) * 100);
    $("progress").classList.add("show");
    $("progress").firstElementChild.style.width = p + "%";
    const left = Math.max(0, duration - s);
    setText("runState", `剩余 ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`);
  } else {
    $("progress").classList.remove("show");
  }
}

function toast(msg, warn) {
  const el = document.createElement("div");
  el.className = "toast" + (warn ? " warn" : "");
  el.innerHTML = (warn ? '<span class="dot"></span>' : "") + `<span>${msg}</span>`;
  toastBox.appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity .3s,transform .3s";
    el.style.opacity = "0"; el.style.transform = "translateX(12px)";
    setTimeout(() => el.remove(), 320);
  }, 3800);
}

/* ---------- 原生回调 ---------- */
window.__tick = (d) => {
  pushSample(d);
  if (running) runS.push(d);
  lastTickAt = performance.now();
  if (d.p) setPowerUI(d.p, d.b);
  updateText(d);
  if ($("sheetSensor").classList.contains("show")) renderSensors(d);
  ensureLoop();
};
window.__power = (src, pct) => {
  setPowerUI(src, pct);
  if (info) info.power = src;
  toast(src === "battery" ? `拔电了（${pct}%）—— 功耗会被限制` : "已接上电源", src === "battery");
};
window.__metricsUnavailable = () => {
  const b = $("banner");
  b.textContent = "数据源 macmon 在这台机器上不可用（只支持 Apple Silicon），图表没数据，但烤机功能照常能用。";
  b.classList.add("show");
  $("aboutSrc").textContent = "不可用（非 Apple Silicon）";
};
window.__note = (msg) => toast(msg, true);
window.__inforefresh = (i) => { renderInfo(i); };
window.__stage = (st) => { setText("runState", `阶梯 ${st}/10 档`); toast(`升到第 ${st} 档`); };
window.__setMode = (m) => {
  if (running) return;
  mode = m; $("targetRow").hidden = mode !== "thermo"; renderModes();
  toast("已切到「" + MODES.find((x) => x.id === m).name + "」");
};
window.__uiStart = () => { if (!running) toggleRun(); };
window.__uiStop = () => { if (running) toggleRun(); };

window.__started = (m) => {
  running = true; startedAt = Date.now(); runS = [];
  mode = m || mode;
  renderModes();
  const b = $("btnStart");
  b.textContent = "停手"; b.classList.add("stop");
  const b2 = $("btnStart2");
  if (b2) { b2.textContent = "停手"; b2.classList.add("stop"); }
  setText("runState", MODES.find((x) => x.id === mode).name + " · 运行中");
  clearInterval(timerId); timerId = setInterval(tickTimer, 250); tickTimer();
};

window.__stopped = () => {
  running = false;
  clearInterval(timerId);
  const b = $("btnStart");
  b.textContent = "开始烤机"; b.classList.remove("stop");
  const b2 = $("btnStart2");
  if (b2) { b2.textContent = "开始烤机"; b2.classList.remove("stop"); }
  setText("runState", t("就绪")); setText("timer", "00:00");
  setText("runNote", "已停止");
  $("progress").classList.remove("show");
  renderModes();
  const s = summary();
  if (s) {
    showSheet(s);
    call("saveRun", { record: { ts: Math.floor(Date.now() / 1000), mode: s.mode, grade: s.grade, cpu: Math.round(s.peakCpu), avg: Math.round(s.avg * 10) / 10, dur: Math.round(s.dur) } })
      .then(loadHistory);
  }
};

/* ---------- 成绩单 ---------- */
function summary() {
  const s = runS;
  if (!s.length) return null;
  const mx = (k) => s.reduce((a, x) => Math.max(a, x[k]), 0);
  const mn = (k) => s.reduce((a, x) => Math.min(a, x[k]), Infinity);
  const avg = s.reduce((a, x) => a + x.aw, 0) / s.length;
  const dur = (Date.now() - startedAt) / 1000;
  const maxPF = mx("pf"), minPF = mn("pf");
  const throttled = maxPF > 0 && minPF < maxPF * 0.75;
  const p = (info && info.pcores) || (info && info.ncpu) || 8;
  const fanless = info && info.fanless;
  const expect = Math.min(60, 6 * p) * (fanless ? 0.7 : 1);

  let grade, desc;
  if (avg / expect >= 0.8 && !throttled) { grade = "S"; desc = "火力全开，调度一点没怂"; }
  else if (avg / expect >= 0.6 && !throttled) { grade = "A"; desc = "很能打，基本跑到满了"; }
  else if (avg / expect >= 0.4) { grade = "B"; desc = "还行，散热或功耗墙拖了后腿"; }
  else { grade = "C"; desc = "压不太动，多半被限制住了"; }

  const badges = [];
  if (mx("ct") < 90) badges.push("满载也没到 90°C");
  if (!throttled) badges.push("全程不降频");
  if (dur >= 300) badges.push("坚持 5 分钟以上");
  else if (dur >= 120) badges.push("撑过 2 分钟");
  if (mx("fan") >= 4000) badges.push("风扇起飞 " + Math.round(mx("fan")) + " RPM");
  if (fanless && mx("fan") === 0) badges.push("全程零噪音");
  if (info && info.power === "battery") badges.push("电池模式下测得");

  return {
    mode, grade, desc, dur, throttled, avg, badges,
    peakCpu: mx("ct"), peakGpu: mx("gt"), peakAll: mx("aw"),
    peakSys: mx("sw"), maxFan: mx("fan"), maxPF, minPF,
  };
}

let historyCache = [];
const bestOf = (arr) => arr.length ? arr.reduce((a, x) => (x.avg > a.avg ? x : a)) : null;

function showSheet(s) {
  $("rGrade").textContent = s.grade;
  $("rDesc").textContent = s.desc;
  $("rMode").textContent = (MODES.find((m) => m.id === s.mode) || {}).name || "成绩单";
  const best = bestOf(historyCache);
  const isRecord = !best || s.avg > best.avg + 0.2;
  $("rRecord").classList.toggle("show", !!isRecord);
  if (isRecord) s.badges.unshift("打破本机纪录 " + s.avg.toFixed(1) + "W");

  const rows = [
    ["持续时长", Math.round(s.dur) + " s"],
    ["CPU 峰值", s.peakCpu.toFixed(0) + " °C"],
    ["GPU 峰值", s.peakGpu.toFixed(0) + " °C"],
    ["芯片功耗峰值", s.peakAll.toFixed(1) + " W"],
    ["功耗均值", s.avg.toFixed(1) + " W"],
    ["整机峰值", s.peakSys.toFixed(0) + " W"],
    ["风扇最高", s.maxFan > 0 ? Math.round(s.maxFan) + " RPM" : "无风扇"],
    ["P 核频率", Math.round(s.minPF) + " – " + Math.round(s.maxPF) + " MHz"],
    ["是否降频", s.throttled ? "有" : "没有"],
  ];
  $("rGrid").innerHTML = rows.map(([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`).join("");
  $("rBadges").innerHTML = s.badges.map((b) => `<span>${b}</span>`).join("");
  openSheet($("sheet"));
  window._report = s;
}

function loadHistory() {
  return call("history").then((r) => {
    historyCache = r.history || [];
    $("histCount").textContent = historyCache.length ? historyCache.length + " 条" : "";
    const tb = $("histBody");
    if (!historyCache.length) {
      tb.innerHTML = '<tr class="empty"><td colspan="6">还没有记录，烤一轮就有了</td></tr>';
      return;
    }
    const best = bestOf(historyCache);
    tb.innerHTML = historyCache.slice(0, 5).map((h) => {
      const d = new Date(h.ts * 1000);
      const t = `${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
      const mname = (MODES.find((m) => m.id === h.mode) || {}).name || h.mode;
      const isBest = best && h.ts === best.ts;
      return `<tr class="${isBest ? "best" : ""}"><td>${t}</td><td>${mname}</td><td class="grade">${h.grade}${isBest ? " ★" : ""}</td><td>${h.cpu}°C</td><td>${h.avg} W</td><td>${h.dur}s</td></tr>`;
    }).join("");
  });
}

/* ---------- 交互 ---------- */
function toggleRun() {
  if (!running) {
    call("params", { duration, target: targetTemp });
    call("start", { mode }).then((r) => { if (r.started_at) battAtStart = r.battery; });
  } else {
    call("stop");
  }
}
$("btnStart").onclick = toggleRun;
$("btnStart2").onclick = toggleRun;

document.querySelectorAll("#durChips button").forEach((b) => {
  b.onclick = () => {
    if (running) { toast("先停手再改时长", true); return; }
    duration = Number(b.dataset.d);
    document.querySelectorAll("#durChips button").forEach((x) => x.classList.toggle("on", x === b));
    if (duration > 0) toast("这一轮会跑 " + (duration / 60) + " 分钟，到点自动停");
  };
});
$("tSlider").oninput = (e) => {
  targetTemp = Number(e.target.value);
  $("tVal").value = targetTemp;
};
$("tVal").onchange = (e) => {
  targetTemp = Math.max(70, Math.min(105, Number(e.target.value) || 95));
  $("tSlider").value = targetTemp;
  $("tVal").value = targetTemp;
};
$("customDur").onchange = (e) => {
  const m = Math.max(1, Math.min(600, Number(e.target.value) || 0));
  if (m > 0) {
    duration = m * 60;
    document.querySelectorAll("#durChips button").forEach((x) => x.classList.remove("on"));
    toast("这一轮会跑 " + m + " 分钟，到点自动停");
  }
};
$("accentCustom").oninput = (e) => {
  if (/^#[0-9A-Fa-f]{6}$/.test(e.target.value)) {
    $("hueVal").textContent = e.target.value.toUpperCase();
    call("set", { key: "accent", value: e.target.value }).then((r) => r.settings && applySettings(r.settings));
  }
};
function hslToHex(h, s, l) {
  h = ((h % 360) + 360) % 360; s /= 100; l /= 100;
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2;
  let r = 0, g = 0, b = 0;
  if (h < 60) { r = c; g = x; } else if (h < 120) { r = x; g = c; } else if (h < 180) { g = c; b = x; }
  else if (h < 240) { g = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
  const to = (v) => Math.round((v + m) * 255).toString(16).padStart(2, "0");
  return "#" + to(r) + to(g) + to(b);
}
function hexToHsv(hex) {
  const n = (hex || "#0A84FF").replace("#", "");
  const r = parseInt(n.substr(0, 2), 16) / 255, g = parseInt(n.substr(2, 2), 16) / 255, b = parseInt(n.substr(4, 2), 16) / 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d !== 0) {
    if (mx === r) h = 60 * (((g - b) / d) % 6);
    else if (mx === g) h = 60 * ((b - r) / d + 2);
    else h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  return [h, (mx === 0 ? 0 : d / mx) * 100, mx * 100];
}
function hsvToHex(h, s, v) {
  h = ((h % 360) + 360) % 360; s /= 100; v /= 100;
  const c = v * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = v - c;
  let r = 0, g = 0, b = 0;
  if (h < 60) { r = c; g = x; } else if (h < 120) { r = x; g = c; } else if (h < 180) { g = c; b = x; }
  else if (h < 240) { g = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
  const to = (v) => Math.round((v + m) * 255).toString(16).padStart(2, "0");
  return "#" + to(r) + to(g) + to(b);
}

/* ---------- 全色域取色板 ---------- */
const SERIES_COLORS = [["c-cpu", "CPU温度"], ["c-gpu", "GPU温度"], ["c-all", "芯片功耗"], ["c-cpuw", "CPU功耗"], ["c-gpuw", "GPU功耗"], ["c-fan", "风扇"], ["c-freq", "频率"]];
const picker = { target: "accent", h: 210, s: 80, v: 100 };
function drawSV() {
  const cv = $("svPad"), g = cv.getContext("2d");
  const w = cv.width, h = cv.height;
  g.fillStyle = hsvToHex(picker.h, 100, 100); g.fillRect(0, 0, w, h);
  let gr = g.createLinearGradient(0, 0, w, 0);
  gr.addColorStop(0, "rgba(255,255,255,1)"); gr.addColorStop(1, "rgba(255,255,255,0)");
  g.fillStyle = gr; g.fillRect(0, 0, w, h);
  gr = g.createLinearGradient(0, 0, 0, h);
  gr.addColorStop(0, "rgba(0,0,0,0)"); gr.addColorStop(1, "rgba(0,0,0,1)");
  g.fillStyle = gr; g.fillRect(0, 0, w, h);
  const x = (picker.s / 100) * w, y = ((100 - picker.v) / 100) * h;
  g.beginPath(); g.arc(x, y, 7, 0, Math.PI * 2);
  g.strokeStyle = picker.v > 55 ? "rgba(0,0,0,.65)" : "rgba(255,255,255,.9)";
  g.lineWidth = 2; g.stroke();
  g.beginPath(); g.arc(x, y, 3, 0, Math.PI * 2); g.fillStyle = "#fff"; g.fill();
}
function drawHue() {
  const cv = $("hueBar"), g = cv.getContext("2d");
  const w = cv.width, h = cv.height;
  const gr = g.createLinearGradient(0, 0, 0, h);
  for (let i = 0; i <= 6; i++) gr.addColorStop(i / 6, hsvToHex(i * 60, 100, 100));
  g.fillStyle = gr; g.fillRect(0, 0, w, h);
  const y = (picker.h / 360) * h;
  g.fillStyle = "#fff"; g.fillRect(0, Math.max(0, y - 3), w, 6);
  g.strokeStyle = "rgba(0,0,0,.35)"; g.strokeRect(0.5, Math.max(0, y - 3) + 0.5, w - 1, 5);
}
function applyPicker() {
  const hex = hsvToHex(picker.h, picker.s, picker.v);
  $("pickerHex").textContent = hex.toUpperCase();
  $("pickerSwatch").style.background = hex;
  if (picker.target === "accent") {
    document.documentElement.style.setProperty("--accent", hex);
    document.documentElement.style.setProperty("--accent-press", shade(hex, -26));
    $("hueVal").textContent = hex.toUpperCase();
    $("accentCustom").value = hex;
  } else {
    C[picker.target] = hex;
    renderSeriesColors();
    redrawAll();
  }
}
function commitPicker() {
  const hex = hsvToHex(picker.h, picker.s, picker.v);
  if (picker.target === "accent") {
    call("set", { key: "accent", value: hex }).then((r) => r.settings && applySettings(r.settings));
  } else {
    call("customColor", { key: picker.target, hex }).then((r) => r.settings && applySettings(r.settings));
  }
}
function openPicker(target, hex) {
  picker.target = target;
  const [h, s, v] = hexToHsv(hex);
  picker.h = h; picker.s = s; picker.v = v;
  $("pickerTarget").textContent = target === "accent" ? "强调色" : (SERIES_COLORS.find((x) => x[0] === target) || ["", ""])[1] + "线";
  $("picker").hidden = false;
  drawSV(); drawHue(); applyPicker();
}
function renderSeriesColors() {
  $("seriesColors").innerHTML = SERIES_COLORS.map(([k, n]) =>
    `<span class="sc" data-k="${k}"><i style="background:${C[k]}"></i>${n}</span>`).join("");
  document.querySelectorAll(".series-colors .sc").forEach((el) => {
    el.onclick = () => openPicker(el.dataset.k, C[el.dataset.k]);
  });
}

$("hueSlider").oninput = (e) => {
  const hex = hslToHex(Number(e.target.value), 70, 52);
  $("hueVal").textContent = hex.toUpperCase();
  $("accentCustom").value = hex;
  document.documentElement.style.setProperty("--accent", hex);
  document.documentElement.style.setProperty("--accent-press", shade(hex, -26));
};
$("hueSlider").onchange = (e) => {
  const hex = hslToHex(Number(e.target.value), 70, 52);
  call("set", { key: "accent", value: hex }).then((r) => r.settings && applySettings(r.settings));
};
$("customIvl").onchange = (e) => {
  const v = Math.max(100, Math.min(5000, Number(e.target.value) || 250));
  call("set", { key: "interval", value: v }).then((r) => r.settings && applySettings(r.settings));
};
$("btnSensor").onclick = () => { openSheet($("sheetSensor")); renderSensors(window._last); };
$("btnCloseSensor").onclick = () => closeSheet($("sheetSensor"));
function renderSensors(d) {
  if (!d) { $("sensorGrid").innerHTML = '<div><span>等待数据…</span></div>'; return; }
  const grid = $("sensorGrid");
  grid.innerHTML = Object.entries(METRICS).map(([k, m]) => {
    const v = d[k];
    return `<div><span>${m.n}</span><b>${m.f(v)}</b><i>${m.u}</i></div>`;
  }).join("");
}
$("hueVal").onclick = () => { const acc = settings && settings.accent ? settings.accent : "#0A84FF"; openPicker("accent", acc); };
$("btnResetChart").onclick = () => { settings.customColors = {}; call("customColor", { key: "_reset", hex: "" }); };
let pickerDrag = false;
$("svPad").addEventListener("mousedown", (e) => {
  pickerDrag = true;
  const r = $("svPad").getBoundingClientRect();
  picker.s = Math.max(0, Math.min(100, (e.clientX - r.left) / r.width * 100));
  picker.v = Math.max(0, Math.min(100, (1 - (e.clientY - r.top) / r.height) * 100));
  drawSV(); applyPicker();
});
$("hueBar").addEventListener("mousedown", (e) => {
  pickerDrag = true;
  const r = $("hueBar").getBoundingClientRect();
  picker.h = Math.max(0, Math.min(360, (e.clientY - r.top) / r.height * 360));
  drawSV(); drawHue(); applyPicker();
});
document.addEventListener("mousemove", (e) => {
  if (!pickerDrag) return;
  if (document.elementFromPoint(e.clientX, e.clientY) === $("svPad")) {
    const r = $("svPad").getBoundingClientRect();
    picker.s = Math.max(0, Math.min(100, (e.clientX - r.left) / r.width * 100));
    picker.v = Math.max(0, Math.min(100, (1 - (e.clientY - r.top) / r.height) * 100));
    drawSV(); applyPicker();
  } else if (document.elementFromPoint(e.clientX, e.clientY) === $("hueBar")) {
    const r = $("hueBar").getBoundingClientRect();
    picker.h = Math.max(0, Math.min(360, (e.clientY - r.top) / r.height * 360));
    drawSV(); drawHue(); applyPicker();
  }
});
document.addEventListener("mouseup", () => { if (pickerDrag) { pickerDrag = false; commitPicker(); } });

function tickClock() { setText("clock", new Date().toTimeString().slice(0, 8)); }

$("btnExport").onclick = exportCSV;
$("btnExport2").onclick = exportCSV;
function exportCSV() {
  if (!runS.length) { toast("先烤一轮才有数据可以导出", true); return; }
  const rows = runS.map((x) => ({
    time: new Date(x.t * 1000).toISOString(),
    cpu_temp_c: x.ct, gpu_temp_c: x.gt,
    cpu_w: x.cw, gpu_w: x.gw, chip_w: x.aw, system_w: x.sw,
    fan_rpm: x.fan, p_freq_mhz: x.pf, cpu_usage_pct: x.cu, gpu_usage_pct: x.gu,
    power: x.p, battery_pct: x.b,
  }));
  call("export", { rows });
  toast("已打开存储面板");
}

let pinned = false;
$("btnPin").onclick = () => {
  pinned = !pinned;
  $("btnPin").classList.toggle("on", pinned);
  call("pin", { on: pinned });
  toast(pinned ? "窗口已置顶" : "已取消置顶");
};
let compact = false;
$("btnCompact").onclick = () => {
  compact = !compact;
  document.body.classList.toggle("compact", compact);
  $("btnCompact").classList.toggle("on", compact);
  call("compact", { on: compact });
  redrawAll();
};

/* 弹层统一管理：spring 淡入，点击遮罩/关闭按钮淡出 */
function openSheet(el) { el.classList.remove("closing"); el.classList.add("show"); }
function closeSheet(el) {
  if (!el.classList.contains("show")) return;
  el.classList.add("closing");
  setTimeout(() => { el.classList.remove("show", "closing"); }, 210);
}
document.querySelectorAll(".sheet-wrap").forEach((w) => {
  w.addEventListener("mousedown", (e) => { if (e.target === w) closeSheet(w); });
});
// 设置面板滚动时标题栏淡出
document.querySelectorAll(".sheet.settings").forEach((el) => {
  el.addEventListener("scroll", (e) => {
    const head = el.querySelector(".settings-head");
    if (head) head.classList.toggle("scrolled", el.scrollTop > 28);
  });
});

$("btnSettings").onclick = () => openSheet($("sheetSet"));
$("btnCloseSet").onclick = () => closeSheet($("sheetSet"));
$("btnDoneSet").onclick = () => closeSheet($("sheetSet"));
$("btnPickWallpaper").onclick = () => call("pickWallpaper");
window.__wallpaperPicked = () => {
  call("set", { key: "wallpaper", value: "custom" }).then((r) => r.settings && applySettings(r.settings));
  toast("壁纸已更新");
};

/* ---------- 验机 ---------- */
$("btnVerify").onclick = () => {
  openSheet($("sheetVerify"));
  $("verifyBody").innerHTML = '<div class="verify-loading">正在采集电池与磁盘数据…</div>';
  call("verify").then((r) => { if (r.verify) renderVerify(r.verify); });
};
$("btnCloseVerify").onclick = () => closeSheet($("sheetVerify"));

function renderVerify(v) {
  const b = v.battery || {};
  const d = v.disk || {};

  let battTag = "good", battLabel = "优";
  if (b.health < 70) { battTag = "bad"; battLabel = "建议更换"; }
  else if (b.health < 85) { battTag = "warn"; battLabel = "良好"; }
  const battBar = b.health >= 70 ? (b.health >= 85 ? "" : "warn") : "bad";

  const writeTB = (d.write_gb || 0) / 1000;
  let diskTag = "good", diskLabel = "健康";
  if (writeTB > 300) { diskTag = "bad"; diskLabel = "写入较多"; }
  else if (writeTB > 100) { diskTag = "warn"; diskLabel = "正常使用"; }
  const diskHealth = Math.max(0, Math.min(100, Math.round(100 - (writeTB / 600) * 100)));
  const diskBar = diskHealth >= 70 ? "" : (diskHealth >= 40 ? "warn" : "bad");

  const score = b.health >= 0 ? b.health : 100;
  let verdict = "good", vTitle = "状态良好", vDesc = "电池与磁盘均在健康范围，这台机器的硬件状况看起来不错。";
  if (battTag === "bad" || diskTag === "bad") { verdict = "bad"; vTitle = "建议检修"; vDesc = "电池或磁盘损耗明显，建议尽快到店检测或更换，使用中留意发热与续航。"; }
  else if (battTag === "warn" || diskTag === "warn") { verdict = "warn"; vTitle = "正常损耗"; vDesc = "这台机器有一定使用痕迹，属正常老化范围，日常使用没有大碍。"; }

  const cyc = b.cycle >= 0 ? b.cycle : "—";
  const des = b.design > 0 ? b.design + " mAh" : "—";
  const full = b.full > 0 ? b.full + " mAh" : "—";

  $("verifyBody").innerHTML = `
    <div class="verdict ${verdict}">
      <div class="v-score">${score}</div>
      <div>
        <div class="v-title">${vTitle}</div>
        <div class="v-desc">${vDesc}</div>
      </div>
    </div>

    <div class="verify-card">
      <h4>机器信息</h4>
      <div class="vr"><span class="k">机型</span><span class="v">${v.model}</span></div>
      <div class="vr"><span class="k">序列号</span><span class="v">${v.serial || "—"}</span></div>
      <div class="vr"><span class="k">芯片</span><span class="v">${v.chip}</span></div>
      <div class="vr"><span class="k">图形</span><span class="v">${v.gpu}</span></div>
      <div class="vr"><span class="k">内存</span><span class="v">${v.ram} GB</span></div>
      <div class="vr"><span class="k">系统</span><span class="v">macOS ${v.macos}</span></div>
    </div>

    <div class="verify-card">
      <h4>电池健康<span class="tag ${battTag}">${battLabel}</span></h4>
      <div class="hbar"><span class="${battBar}" style="width:${b.health >= 0 ? b.health : 0}%"></span></div>
      <div class="vr"><span class="k">健康度</span><span class="v">${b.health >= 0 ? b.health + "%" : "—"}</span></div>
      <div class="vr"><span class="k">循环次数</span><span class="v">${cyc} 次</span></div>
      <div class="vr"><span class="k">当前满充</span><span class="v">${full}</span></div>
      <div class="vr"><span class="k">设计容量</span><span class="v">${des}</span></div>
      <div class="vr"><span class="k">状态</span><span class="v">${b.condition || "—"}</span></div>
    </div>

    <div class="verify-card">
      <h4>磁盘寿命<span class="tag ${diskTag}">${diskLabel}</span></h4>
      <div class="hbar"><span class="${diskBar}" style="width:${diskHealth}%"></span></div>
      <div class="vr"><span class="k">累计写入</span><span class="v">${writeTB.toFixed(2)} TB</span></div>
      <div class="vr"><span class="k">累计读取</span><span class="v">${((d.read_gb || 0) / 1000).toFixed(2)} TB</span></div>
      <div class="vr"><span class="k">估算寿命</span><span class="v">${diskHealth}%</span></div>
    </div>

    <div style="font-size:.78em;color:var(--text-3);line-height:1.6">仅供参考：电池健康度来自系统数据；磁盘寿命按累计写入量与典型 SSD 写入寿命估算；序列号可用于在 Apple 官网查询保修与激活状态。</div>`;
}
$("btnClearHistory").onclick = () => call("clearHistory").then(loadHistory);
$("btnAgain").onclick = () => closeSheet($("sheet"));
$("btnCopy").onclick = copyReport;
$("btnImage").onclick = exportImage;

function copyReport() {
  const s = window._report; if (!s) return;
  const txt =
`烤机台成绩单
机型  ${info.display_name} · ${info.chip} · ${info.ncpu} 核 · ${info.memory_gb}GB
模式  ${(MODES.find((m) => m.id === s.mode) || {}).name}
评级  ${s.grade} —— ${s.desc}
时长  ${Math.round(s.dur)}s    CPU 峰值 ${s.peakCpu.toFixed(0)}°C    GPU 峰值 ${s.peakGpu.toFixed(0)}°C
功耗  芯片峰值 ${s.peakAll.toFixed(1)}W / 均值 ${s.avg.toFixed(1)}W    整机峰值 ${s.peakSys.toFixed(0)}W
风扇  ${s.maxFan > 0 ? Math.round(s.maxFan) + " RPM" : "无风扇"}    ${s.throttled ? "期间有降频" : "全程不降频"}
${s.badges.join(" · ")}`;
  const done = () => {
    const b = $("btnCopy"); b.textContent = "已拷贝";
    setTimeout(() => (b.textContent = "拷贝成绩"), 1600);
  };
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(txt).then(done).catch(() => fallbackCopy(txt, done));
  } else fallbackCopy(txt, done);
}
function fallbackCopy(txt, done) {
  const ta = document.createElement("textarea");
  ta.value = txt; ta.style.position = "fixed"; ta.style.opacity = "0";
  document.body.appendChild(ta); ta.select();
  document.execCommand("copy"); ta.remove(); done();
}

// 成绩单导出成 PNG，直接发群
function exportImage() {
  const s = window._report; if (!s) return;
  const W = 1080, H = 1440;
  const cv = document.createElement("canvas");
  cv.width = W; cv.height = H;
  const g = cv.getContext("2d");
  const dark = document.documentElement.dataset.theme !== "light";
  g.fillStyle = dark ? "#141416" : "#F5F5F7";
  g.fillRect(0, 0, W, H);
  g.fillStyle = dark ? "#F5F5F7" : "#1D1D1F";
  g.textBaseline = "top";
  g.font = "600 40px -apple-system,'PingFang SC',sans-serif";
  g.fillText("烤机台成绩单", 80, 80);
  g.font = "24px -apple-system,'PingFang SC',sans-serif";
  g.fillStyle = dark ? "rgba(235,235,245,.6)" : "rgba(60,60,67,.6)";
  g.fillText(info.display_name + " · " + info.chip, 80, 140);
  g.fillText((MODES.find((m) => m.id === s.mode) || {}).name + " · 持续 " + Math.round(s.dur) + " 秒", 80, 176);

  g.fillStyle = "#0A84FF";
  g.beginPath();
  if (g.roundRect) g.roundRect(80, 250, 210, 210, 42); else g.rect(80, 250, 210, 210);
  g.fill();
  g.fillStyle = "#fff";
  g.font = "300 140px -apple-system,sans-serif";
  g.fillText(s.grade, 138, 282);
  g.fillStyle = dark ? "#F5F5F7" : "#1D1D1F";
  g.font = "500 34px -apple-system,'PingFang SC',sans-serif";
  g.fillText(s.desc, 340, 300);
  g.font = "24px -apple-system,'PingFang SC',sans-serif";
  g.fillStyle = dark ? "rgba(235,235,245,.6)" : "rgba(60,60,67,.6)";
  g.fillText("芯片功耗均值 " + s.avg.toFixed(1) + " W · 峰值 " + s.peakAll.toFixed(1) + " W", 340, 352);

  const rows = [
    ["CPU 峰值", s.peakCpu.toFixed(0) + " °C"],
    ["GPU 峰值", s.peakGpu.toFixed(0) + " °C"],
    ["整机峰值", s.peakSys.toFixed(0) + " W"],
    ["风扇最高", s.maxFan > 0 ? Math.round(s.maxFan) + " RPM" : "无风扇"],
    ["P 核频率", Math.round(s.minPF) + " – " + Math.round(s.maxPF) + " MHz"],
    ["是否降频", s.throttled ? "有" : "没有"],
  ];
  rows.forEach(([k, v], i) => {
    const x = 80 + (i % 2) * 470, y = 540 + Math.floor(i / 2) * 130;
    g.fillStyle = dark ? "rgba(255,255,255,.05)" : "rgba(0,0,0,.035)";
    g.beginPath();
    if (g.roundRect) g.roundRect(x, y, 440, 110, 20); else g.rect(x, y, 440, 110);
    g.fill();
    g.fillStyle = dark ? "rgba(235,235,245,.55)" : "rgba(60,60,67,.6)";
    g.font = "22px -apple-system,'PingFang SC',sans-serif";
    g.fillText(k, x + 26, y + 22);
    g.fillStyle = dark ? "#F5F5F7" : "#1D1D1F";
    g.font = "400 34px -apple-system,'PingFang SC',sans-serif";
    g.fillText(v, x + 26, y + 56);
  });

  g.font = "24px -apple-system,'PingFang SC',sans-serif";
  let y = 990;
  s.badges.forEach((b) => {
    g.fillStyle = dark ? "rgba(255,255,255,.07)" : "rgba(0,0,0,.05)";
    const w = g.measureText(b).width + 40;
    g.beginPath();
    if (g.roundRect) g.roundRect(80, y, w, 46, 23); else g.rect(80, y, w, 46);
    g.fill();
    g.fillStyle = dark ? "#F5F5F7" : "#1D1D1F";
    g.fillText(b, 100, y + 10);
    y += 58;
  });

  g.fillStyle = dark ? "rgba(235,235,245,.35)" : "rgba(60,60,67,.4)";
  g.font = "20px -apple-system,'PingFang SC',sans-serif";
  g.fillText(new Date().toLocaleString("zh-CN") + " · 数据来自本机 macmon", 80, H - 70);

  const url = cv.toDataURL("image/png");
  call("exportImage", { data: url.split(",")[1] });
  toast("已打开存储面板");
}

/* ---------- 设置 ---------- */
function applySettings(s) {
  settings = s;
  intervalMs = s.interval; windowSec = s.windowSec;
  cap = Math.max(120, Math.round((windowSec * 1000) / intervalMs));
  document.documentElement.dataset.theme = s.dark ? "dark" : "light";
  lang = resolveLang(s.lang || "auto");
  applyLang();

  document.querySelectorAll(".seg").forEach((seg) => {
    const k = seg.dataset.key;
    seg.querySelectorAll("button").forEach((b) => b.classList.toggle("on", String(s[k]) === b.dataset.v));
  });
  $("setFuse").checked = s.fuse;
  $("setFuseTemp").value = s.fuseTemp;
  $("fuseVal").textContent = s.fuseTemp + " °C";
  $("setPeak").checked = s.showPeak;
  setText("ivl", s.interval + " ms");
  if (s.accent) {
    document.documentElement.style.setProperty("--accent", s.accent);
    document.documentElement.style.setProperty("--accent-press", shade(s.accent, -26));
  } else {
    document.documentElement.style.removeProperty("--accent");
    document.documentElement.style.removeProperty("--accent-press");
  }
  document.body.dataset.wallpaper = s.wallpaper || "none";
  if (s.wallpaper === "custom") {
    document.body.style.backgroundImage = 'url("roast://wallpaper?v=' + Date.now() + '")';
    document.body.style.backgroundSize = "cover";
    document.body.style.backgroundPosition = "center";
  } else {
    document.body.style.backgroundImage = "";
    document.body.style.backgroundSize = "";
    document.body.style.backgroundPosition = "";
  }
  if (s.glassAlpha != null) {
    $("glassSlider").value = s.glassAlpha;
    $("glassVal").textContent = s.glassAlpha + "%";
    document.documentElement.style.setProperty("--glass-alpha", s.glassAlpha / 100);
  }
  if (s.radius) document.documentElement.style.setProperty("--radius", s.radius + "px");
  if (s.sideWidth) document.documentElement.style.setProperty("--side-w", s.sideWidth + "px");
  if (s.fontSize != null) {
    document.documentElement.style.setProperty("--fs", s.fontSize + "px");
    $("fontSlider").value = s.fontSize;
    $("fontVal").textContent = s.fontSize + " px";
  }
  document.body.dataset.density = s.density || "standard";
  if ($("setFill")) $("setFill").checked = s.chartFill !== false;
  if (s.dashboard) {
    try { const d = JSON.parse(s.dashboard); if (Array.isArray(d) && d.length) layout = d; } catch (e) {}
  }
  applyLayout();
  renderSwatches();
  renderSeriesColors();
  refreshColors();
  redrawAll();
}

/* 色板 / 壁纸 渲染 */
function renderSwatches() {
  const acc = settings ? (settings.accent || "") : "";
  $("accentSwatches").innerHTML = ACCENTS.map((c) =>
    `<span class="swc ${c === acc ? "on" : ""}" data-c="${c}" style="background:${c || (document.documentElement.dataset.theme === "light" ? "#007AFF" : "#0A84FF")}"></span>`).join("");
  document.querySelectorAll("#accentSwatches .swc").forEach((el) => {
    el.onclick = () => call("set", { key: "accent", value: el.dataset.c }).then((r) => r.settings && applySettings(r.settings));
  });
  const ct = settings ? (settings.chartTheme || "apple") : "apple";
  $("chartSwatches").innerHTML = Object.entries(CHART_THEMES).map(([id, t]) =>
    `<span class="swc ${id === ct ? "on" : ""}" data-c="${id}" title="${t.name}" style="background:linear-gradient(135deg,${t.c_cpu} 0 33%,${t.c_all} 33% 66%,${t.c_fan} 66% 100%)"></span>`).join("");
  document.querySelectorAll("#chartSwatches .swc").forEach((el) => {
    el.onclick = () => call("set", { key: "chartTheme", value: el.dataset.c }).then((r) => r.settings && applySettings(r.settings));
  });
  const wp = settings ? (settings.wallpaper || "none") : "none";
  $("wallSwatches").innerHTML = WALLPAPERS.map((w) =>
    `<span class="swc ${w.id === wp ? "on" : ""} ${w.id !== "none" ? "wp-" + w.id : ""}" data-c="${w.id}" title="${w.name}"></span>`).join("");
  document.querySelectorAll("#wallSwatches .swc").forEach((el) => {
    el.onclick = () => {
      if (el.dataset.c === "custom") { call("pickWallpaper"); return; }
      call("set", { key: "wallpaper", value: el.dataset.c }).then((r) => r.settings && applySettings(r.settings));
    };
  });
  $("accentCustom").value = /^#[0-9A-Fa-f]{6}$/.test(acc) ? acc : "#0A84FF";
  $("hueVal").textContent = $("accentCustom").value.toUpperCase();
}

document.querySelectorAll(".seg button").forEach((b) => {
  b.onclick = () => {
    const seg = b.parentElement;
    const key = seg.dataset.key;
    const v = (key === "interval" || key === "windowSec" || key === "sideWidth" || key === "radius" || key === "chartLine") ? Number(b.dataset.v) : b.dataset.v;
    call("set", { key, value: v }).then((r) => { if (r.settings) applySettings(r.settings); });
  };
});
$("setFuse").onchange = (e) => call("set", { key: "fuse", value: e.target.checked }).then((r) => r.settings && applySettings(r.settings));
$("setPeak").onchange = (e) => call("set", { key: "showPeak", value: e.target.checked }).then((r) => r.settings && applySettings(r.settings));
$("setFill").onchange = (e) => call("set", { key: "chartFill", value: e.target.checked }).then((r) => r.settings && applySettings(r.settings));
$("setFuseTemp").oninput = (e) => {
  $("fuseVal").textContent = e.target.value + " °C";
  call("set", { key: "fuseTemp", value: Number(e.target.value) }).then((r) => r.settings && applySettings(r.settings));
};
$("setThreads").oninput = (e) => {
  const n = Number(e.target.value);
  $("thrVal").textContent = n === 0 ? "自动（按模式）" : n + " 个线程";
  call("params", { threads: n });
};
$("setLogin").onchange = (e) => {
  call("loginItem", { on: e.target.checked }).then((r) => {
    if (!r.ok) { toast("登录项设置失败（未签名应用可能被系统拦）", true); e.target.checked = !e.target.checked; }
  });
};
$("btnHardware").onclick = () => {
  openSheet($("sheetHw"));
  call("hardware").then((r) => {
    if (!r.hw) return;
    const h = r.hw;
    const rows = [
      ["机型", h.model], ["标识符", h.id], ["处理器", h.chip],
      ["图形", h.gpu], ["核心", `${h.cores}（${h.pcores}P + ${h.ecores}E）`],
      ["内存", h.ram], ["macOS", h.macos], ["磁盘总容量", h.disk_total],
      ["磁盘可用", h.disk_free], ["已开机", h.uptime], ["电池循环", h.cycles],
      ["供电", h.power === "battery" ? "电池" : "外接电源"],
    ];
    $("hwGrid").innerHTML = rows.map(([k, v]) => `<div><span>${k}</span><b>${v || "—"}</b></div>`).join("");
  });
};
$("btnCloseHw").onclick = () => closeSheet($("sheetHw"));
$("btnReset").onclick = () => call("restoreDefaults").then((r) => {
  if (r.settings) { applySettings(r.settings); toast("已恢复默认设置"); }
});

/* ---------- 窗口拖动：空白处按下即拖，交给原生 ---------- */
document.addEventListener("mousedown", (e) => {
  if (editMode) return;  // 编辑模式下专注编辑，不触发窗口拖动
  const skip = e.target.closest("button, input, select, a, .mode, canvas, .seg, .stepper, .sw, .slider, .handle, .rz");
  if (skip) return;
  call("drag");
});
document.addEventListener("dragstart", (e) => e.preventDefault());

document.addEventListener("keydown", (e) => {
  const meta = e.metaKey || e.ctrlKey;
  if (meta && (e.key === "r" || e.key === "R")) { e.preventDefault(); toggleRun(); }
  else if (meta && e.key === ",") {
    e.preventDefault();
    const s = $("sheetSet");
    s.classList.contains("show") ? closeSheet(s) : openSheet(s);
  }
  else if (meta && (e.key === "e" || e.key === "E")) { e.preventDefault(); exportCSV(); }
  else if (meta && (e.key === "d" || e.key === "D")) {
    e.preventDefault();
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    call("set", { key: "theme", value: next }).then((r) => r.settings && applySettings(r.settings));
  } else if (e.key === "Escape") {
    closeSheet($("sheet"));
    closeSheet($("sheetSet"));
    closeSheet($("sheetHw"));
    closeSheet($("sheetSensor"));
    closeSheet($("sheetVerify"));
    closeZoom();
  }
});

window.addEventListener("resize", redrawAll);

/* ---------- 启动 ---------- */
function recommend(i) {
  if (i.fanless) return "passive";
  if (!i.apple_silicon) return "cpu";
  return "max";
}
function hintFor(i) {
  if (i.fanless) return "这台没有风扇，热量散不掉，建议用凉拌模式，别一次烤太久。";
  if (i.power === "battery") return "现在是电池供电，满功耗会被砍。想跑满记得插上电。";
  if (!i.apple_silicon) return "Intel 机型温度墙敏感，建议短时多轮，中间让机器喘口气。";
  if (/Mac mini|Mac Studio|Mac Pro|iMac/.test(i.display_name || "")) return "台式机身散热余量大，极限模式可以放心长时间跑。";
  return "十种模式：恒温模式能让机器稳在你指定的温度，阶梯升载能找出功耗拐点。";
}

async function boot() {
  window.webkit.messageHandlers.api.postMessage({ op: "ready" });
  refreshColors();

  charts = [
    new Chart("cvTemp", CHART_DEFS.temp),
    new Chart("cvPower", CHART_DEFS.power),
    new Chart("cvFan", CHART_DEFS.fan),
  ];
  const chartMap = { cvTemp: "temp", cvPower: "power", cvFan: "fan" };
  charts.forEach((ch) => {
    ch.cv.addEventListener("click", () => openZoom(ch));
    const nm = chartMap[ch.cv.id];
    ch.legendEl = $("lg" + nm.charAt(0).toUpperCase() + nm.slice(1));
    const cap = nm.charAt(0).toUpperCase() + nm.slice(1);
    ["A", "B", "C"].forEach((slot) => {
      const sel = $("s" + cap + slot);
      if (!sel) return;
      sel.innerHTML = (slot === "C" ? '<option value="">无</option>' : "") +
        Object.entries(METRICS).map(([k, m]) => `<option value="${k}">${m.n}</option>`).join("");
      sel.value = ch.keys[slot === "A" ? 0 : slot === "B" ? 1 : 2] || "";
      sel.onchange = () => {
        const ks = ["A", "B", "C"].map((x) => $("s" + cap + x).value).filter((v) => v);
        ch.setKeys(ks);
        updateText(window._last || {});
        redrawAll();
      };
    });
  });

  const first = await call("info");
  if (first.settings) applySettings(first.settings);
  renderInfo(first.info);
  if (first.running) {
    running = true; startedAt = Date.now(); mode = first.mode;
    setText("runState", "运行中");
    $("btnStart").textContent = "停手"; $("btnStart").classList.add("stop");
    timerId = setInterval(tickTimer, 250);
  }
  if (settings && settings.defaultMode && settings.defaultMode !== "auto") mode = settings.defaultMode;
  renderModes();
  redrawAll();
  loadHistory();
  tickClock();
  setInterval(tickClock, 1000);
  $("aboutSrc").textContent = "macmon · 内嵌";
}

/* ================= 模块化仪表盘（无极 resize + 拖拽交换） ================= */
const MODULE_DEFS = {
  "hero-cpu": { title: "CPU 温度" }, "hero-gpu": { title: "GPU 温度" },
  "hero-aw": { title: "芯片功耗" }, "hero-fan": { title: "风扇转速" },
  "temp": { title: "温度曲线", resizable: true }, "power": { title: "功耗曲线", resizable: true },
  "fan": { title: "风扇与频率", resizable: true },
  "peaks": { title: "本轮峰值" }, "history": { title: "本机纪录" },
};
const DEFAULT_LAYOUT = [
  { id: "hero-cpu", span: 3 }, { id: "hero-gpu", span: 3 },
  { id: "hero-aw", span: 3 }, { id: "hero-fan", span: 3 },
  { id: "temp", span: 12, h: 132 }, { id: "power", span: 12, h: 132 },
  { id: "fan", span: 12, h: 132 }, { id: "peaks", span: 12 }, { id: "history", span: 12 },
];
let layout = DEFAULT_LAYOUT.map((x) => Object.assign({}, x));
const findL = (id) => layout.find((m) => m.id === id);

function applyLayout() {
  const dash = $("dashboard");
  if (!dash) return;
  layout.forEach((m) => {
    const el = dash.querySelector(`[data-mod="${m.id}"]`);
    if (!el) return;
    el.style.setProperty("--mspan", m.span);
    el.classList.toggle("hidden", !!m.hidden);
    setModHeight(el, m);
    dash.appendChild(el);
  });
  setTimeout(redrawAll, 60);
}
function setModHeight(el, m) {
  if (m.h == null) return;
  const def = MODULE_DEFS[m.id];
  if (def && def.resizable) {
    const cv = el.querySelector("canvas");
    if (cv) cv.style.height = m.h + "px";
  }
}
function applyLight(m) {
  const el = $("dashboard").querySelector(`[data-mod="${m.id}"]`);
  if (!el) return;
  el.style.setProperty("--mspan", m.span);
  setModHeight(el, m);
  redrawAll();
}
function saveLayout() { call("saveDashboard", { json: JSON.stringify(layout) }); }

/* 右键快捷调节 */
let ctxTarget = null;
function openCtx(id, x, y) {
  ctxTarget = id;
  const m = findL(id), def = MODULE_DEFS[id];
  const widthOpts = [[3, "¼"], [6, "½"], [9, "¾"], [12, "全"]];
  const hOpts = [[96, "矮"], [132, "中"], [200, "高"]];
  const html = `<div class="cm-title">${def.title} · 宽 ${m.span}/12 · ${def.resizable ? "高 " + m.h + "px" : ""}</div>
    <div class="cm-item"><span>宽度</span><span class="cm-opt">${widthOpts.map(([v, n]) => `<b class="${m.span === v ? "on" : ""}" data-span="${v}">${n}</b>`).join("")}</span></div>
    ${def.resizable ? `<div class="cm-item"><span>高度</span><span class="cm-opt">${hOpts.map(([v, n]) => `<b class="${m.h === v ? "on" : ""}" data-h="${v}">${n}</b>`).join("")}</span></div>` : ""}
    <div class="cm-sep"></div>
    <div class="cm-item" data-act="up">上移</div>
    <div class="cm-item" data-act="down">下移</div>
    <div class="cm-item" data-act="toggle">${m.hidden ? "显示此卡片" : "隐藏此卡片"}</div>
    <div class="cm-item danger" data-act="reset">重置此卡片</div>`;
  const menu = $("ctxMenu");
  menu.innerHTML = html;
  menu.hidden = false;
  menu.style.left = Math.min(x, window.innerWidth - 200) + "px";
  menu.style.top = Math.min(y, window.innerHeight - 300) + "px";
  menu.querySelectorAll("[data-span]").forEach((b) => b.onclick = () => { m.span = Number(b.dataset.span); applyLayout(); saveLayout(); closeCtx(); });
  menu.querySelectorAll("[data-h]").forEach((b) => b.onclick = () => { m.h = Number(b.dataset.h); applyLayout(); saveLayout(); closeCtx(); });
  menu.querySelectorAll("[data-act]").forEach((it) => it.onclick = () => {
    const act = it.dataset.act, idx = layout.indexOf(m);
    if (act === "up" && idx > 0) { [layout[idx], layout[idx - 1]] = [layout[idx - 1], layout[idx]]; }
    else if (act === "down" && idx < layout.length - 1) { [layout[idx], layout[idx + 1]] = [layout[idx + 1], layout[idx]]; }
    else if (act === "toggle") m.hidden = !m.hidden;
    else if (act === "reset") { const d = DEFAULT_LAYOUT.find((x) => x.id === id) || {}; m.span = d.span || 12; m.h = d.h; m.hidden = false; }
    applyLayout(); saveLayout(); closeCtx();
  });
}
function closeCtx() { $("ctxMenu").hidden = true; ctxTarget = null; }

document.addEventListener("contextmenu", (e) => {
  const mod = e.target.closest(".module");
  if (!mod) return;
  e.preventDefault();
  openCtx(mod.dataset.mod, e.clientX, e.clientY);
});
document.addEventListener("click", (e) => { if (!$("ctxMenu").contains(e.target)) closeCtx(); });

/* 编辑模式：拖拽交换 + 无极 resize */
let editMode = false, dragMod = null, dragGhost = null, resizeMod = null, resizeStart = null;
function setEdit(on) {
  editMode = on;
  document.body.classList.toggle("editing", on);
  $("btnEdit").classList.toggle("on", on);
  toast(on ? "编辑模式：拖 ⠿ 交换位置，拖右下角 ⠓ 调宽高" : "已退出编辑");
}
$("btnEdit").onclick = () => setEdit(!editMode);
$("btnResetLayout").onclick = () => { layout = DEFAULT_LAYOUT.map((x) => Object.assign({}, x)); applyLayout(); saveLayout(); toast("布局已重置"); };

document.addEventListener("mousedown", (e) => {
  if (!editMode) return;
  if (e.target.closest(".rz")) {
    resizeMod = e.target.closest(".module");
    const m = findL(resizeMod.dataset.mod);
    resizeStart = { x: e.clientX, y: e.clientY, span: m.span, h: m.h };
    e.preventDefault();
    return;
  }
  const h = e.target.closest(".handle");
  if (h) {
    dragMod = h.closest(".module");
    dragMod.classList.add("dragging");
    e.preventDefault();
  }
});

document.addEventListener("mousemove", (e) => {
  if (resizeMod) {
    const m = findL(resizeMod.dataset.mod);
    const dashW = $("dashboard").getBoundingClientRect().width;
    const colW = Math.max(1, dashW / 12);
    const dSpan = Math.round((e.clientX - resizeStart.x) / colW);
    m.span = Math.max(1, Math.min(12, resizeStart.span + dSpan));
    if (MODULE_DEFS[m.id] && MODULE_DEFS[m.id].resizable && resizeStart.h != null) {
      m.h = Math.round(Math.max(80, Math.min(400, resizeStart.h + (e.clientY - resizeStart.y))));
    }
    applyLight(m);
    return;
  }
  if (!dragMod) return;
  const els = [...$("dashboard").querySelectorAll(".module:not(.dragging)")];
  els.forEach((el) => el.classList.remove("drop-before", "drop-after"));
  const target = els.find((el) => {
    const r = el.getBoundingClientRect();
    return e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
  });
  if (target) {
    target.classList.add("drop-before");
    dragGhost = { target };
  } else dragGhost = null;
});

document.addEventListener("mouseup", () => {
  if (resizeMod) {
    saveLayout();
    resizeMod = null; resizeStart = null;
    applyLayout();
  }
  if (!dragMod) return;
  dragMod.classList.remove("dragging");
  [...document.querySelectorAll(".module")].forEach((el) => el.classList.remove("drop-before", "drop-after"));
  if (dragGhost) {
    const a = findL(dragMod.dataset.mod);
    const b = findL(dragGhost.target.dataset.mod);
    if (a && b && a !== b) {
      // 交换位置（DOM 顺序）+ 交换尺寸（自适应）
      const ai = layout.indexOf(a), bi = layout.indexOf(b);
      [layout[ai], layout[bi]] = [layout[bi], layout[ai]];
      const ts = layout[ai].span, th = layout[ai].h;
      layout[ai].span = layout[bi].span; layout[ai].h = layout[bi].h;
      layout[bi].span = ts; layout[bi].h = th;
      applyLayout(); saveLayout();
    }
  }
  dragMod = null; dragGhost = null;
});

/* 玻璃透明度 */
$("glassSlider").oninput = (e) => {
  const v = Number(e.target.value);
  $("glassVal").textContent = v + "%";
  document.documentElement.style.setProperty("--glass-alpha", v / 100);
};
$("glassSlider").onchange = (e) => call("setGlass", { value: Number(e.target.value) });

// 字体大小无极调节
$("fontSlider").oninput = (e) => {
  const v = Number(e.target.value);
  $("fontVal").textContent = v + " px";
  document.documentElement.style.setProperty("--fs", v + "px");
};
$("fontSlider").onchange = (e) => {
  const v = Number(e.target.value);
  call("set", { key: "fontSize", value: v }).then((r) => r.settings && applySettings(r.settings));
};

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && editMode) { setEdit(false); }
});

/* ================= 图表全屏缩放 ================= */
const zoom = { chart: null, x0: 0, x1: 1, drag: false, lastX: 0, lastY: 0 };
function openZoom(ch) {
  zoom.chart = ch;
  zoom.x0 = 0; zoom.x1 = 1;
  $("zoomTitle").textContent = ch.def.title;
  buildZoomLegend();
  $("zoomWrap").classList.add("show");
  resizeZoom();
  renderZoom();
}
function closeZoom() { $("zoomWrap").classList.remove("show"); }
function buildZoomLegend() {
  const ch = zoom.chart;
  $("zoomLegend").innerHTML = ch.series.map((sr) =>
    `<span><i style="background:${sr.color()}${sr.dashed ? ';border-top:2px dashed ' + sr.color() : ''}"></i>${sr.name}</span>`).join("");
}
function resizeZoom() {
  const body = $("zoomWrap").querySelector(".zoom-body");
  const cv = $("zoomCanvas");
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = body.clientWidth, h = body.clientHeight;
  cv.width = Math.max(1, Math.floor(w * dpr));
  cv.height = Math.max(1, Math.floor(h * dpr));
  cv.style.width = w + "px"; cv.style.height = h + "px";
}
function renderZoom() {
  const ch = zoom.chart;
  const cv = $("zoomCanvas");
  const g = cv.getContext("2d");
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const fs = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--fs")) || 13;
  const W = cv.width, H = cv.height;
  g.clearRect(0, 0, W, H);
  const data = longHist;
  const n = data.length;
  if (n < 2) return;

  const padL = Math.round(fs * 4) + 8, padR = 16, padT = 16, padB = Math.round(fs) + 18;
  const pw = W - padL - padR, ph = H - padT - padB;

  // 可视数据范围（按时间比例）
  const i0 = Math.max(0, Math.floor(zoom.x0 * (n - 1)));
  const i1 = Math.min(n - 1, Math.ceil(zoom.x1 * (n - 1)));

  // 取可视范围内各序列的 min/max
  const keys = ch.keys;
  let lo = Infinity, hi = -Infinity;
  for (let i = i0; i <= i1; i++) {
    for (const k of keys) { const v = data[i][k]; if (v < lo) lo = v; if (v > hi) hi = v; }
  }
  if (!isFinite(lo)) return;
  const pad = (hi - lo || 1) * 0.12;
  const top = hi + pad, bot = Math.max(0, lo - pad);
  const Y = (v) => padT + ph - ((v - bot) / (top - bot || 1)) * ph;

  // 网格 + 刻度（nice ticks）
  const rough = (top - bot) / 4, mag = Math.pow(10, Math.floor(Math.log10(rough || 1)));
  const norm = rough / mag, step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
  const gridBot = Math.floor(bot / step) * step;
  g.font = `600 ${fs + 2}px -apple-system,SF Pro Text,Menlo,monospace`;
  g.textAlign = "right";
  const fmtV = (v) => v >= 1000 ? (v / 1000).toFixed(v % 1000 ? 1 : 0) + "k" : (Number.isInteger(v) ? v : v.toFixed(1));
  for (let v = gridBot; v <= top + step; v += step) {
    const y = Math.round(padT + ph - ((v - bot) / (top - bot)) * ph) + .5;
    g.strokeStyle = C.grid; g.lineWidth = 1;
    g.beginPath(); g.moveTo(padL, y); g.lineTo(W - padR, y); g.stroke();
    g.fillStyle = C.text2; g.fillText(fmtV(v), padL - 8, y + 3.5);
  }

  // 曲线
  const X = (i) => padL + ((i - i0) / (i1 - i0 || 1)) * pw;
  ch.series.forEach((sr) => {
    g.save();
    g.beginPath(); g.rect(padL, 0, pw, H); g.clip();
    g.beginPath();
    for (let i = i0; i <= i1; i++) {
      const x = X(i), y = Y(data[i][sr.key]);
      i === i0 ? g.moveTo(x, y) : g.lineTo(x, y);
    }
    g.strokeStyle = sr.color();
    g.lineWidth = (settings && settings.chartLine) || 1.6;
    if (sr.dashed) g.setLineDash([5, 4]);
    g.lineJoin = "round"; g.lineCap = "round";
    g.stroke();
    g.restore();
  });

  // 底部时间轴
  const t0 = data[i0].t, t1 = data[i1].t;
  g.textAlign = "center"; g.font = `600 ${fs + 1}px -apple-system,SF Pro Text,Menlo,monospace`;
  const ticks = 5;
  for (let i = 0; i < ticks; i++) {
    const frac = i / (ticks - 1);
    const x = padL + pw * frac;
    g.fillStyle = C.text2;
    g.fillText(fmtClock(t0 + (t1 - t0) * frac), x, H - 8);
  }
}
function fmtClock(ts) {
  const d = new Date(ts * 1000);
  return d.getHours() + ":" + String(d.getMinutes()).padStart(2, "0") + ":" + String(d.getSeconds()).padStart(2, "0");
}
$("btnCloseZoom").onclick = closeZoom;
$("zoomWrap").addEventListener("mousedown", (e) => { if (e.target === $("zoomWrap")) closeZoom(); });
// 触控板双指缩放 + 拖拽平移
$("zoomCanvas").addEventListener("wheel", (e) => {
  e.preventDefault();
  const body = $("zoomWrap").querySelector(".zoom-body");
  const rect = body.getBoundingClientRect();
  const fx = (e.clientX - rect.left) / rect.width;
  const span = zoom.x1 - zoom.x0;
  if (e.ctrlKey) {
    // pinch 缩放
    const factor = e.deltaY > 0 ? 1.12 : 0.89;
    const newSpan = Math.max(0.02, Math.min(1, span * factor));
    const center = zoom.x0 + span * fx;
    zoom.x0 = Math.max(0, center - newSpan * fx);
    zoom.x1 = Math.min(1, zoom.x0 + newSpan);
    if (zoom.x1 - zoom.x0 < 0.02) { zoom.x0 = Math.max(0, zoom.x1 - 0.02); }
  } else {
    // 平移
    const dx = (e.deltaX || e.deltaY) * 0.001;
    zoom.x0 = Math.max(0, Math.min(1 - span, zoom.x0 + dx));
    zoom.x1 = zoom.x0 + span;
  }
  renderZoom();
}, { passive: false });
$("zoomCanvas").addEventListener("mousedown", (e) => {
  zoom.drag = true; zoom.lastX = e.clientX;
  $("zoomCanvas").classList.add("dragging");
  e.preventDefault();
});
document.addEventListener("mousemove", (e) => {
  if (!zoom.drag || !$("zoomWrap").classList.contains("show")) return;
  const body = $("zoomWrap").querySelector(".zoom-body");
  const dx = (zoom.lastX - e.clientX) / body.clientWidth;
  zoom.lastX = e.clientX;
  const span = zoom.x1 - zoom.x0;
  zoom.x0 = Math.max(0, Math.min(1 - span, zoom.x0 + dx));
  zoom.x1 = zoom.x0 + span;
  renderZoom();
});
document.addEventListener("mouseup", () => {
  zoom.drag = false;
  $("zoomCanvas").classList.remove("dragging");
});
window.addEventListener("resize", () => { if ($("zoomWrap").classList.contains("show")) { resizeZoom(); renderZoom(); } });

boot();
