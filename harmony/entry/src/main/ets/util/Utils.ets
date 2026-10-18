/**
 * 通用工具：Base64、URL 解码、稳定 ID、日志总线
 */
import util from '@ohos.util';
import { AppConfig } from '../common/AppConfig';

/** 兼容 URL-safe Base64 与缺失 padding 的解码 */
export function decodeBase64Compat(rawValue: string): string {
  const normalized: string = rawValue.trim().replace(/-/g, '+').replace(/_/g, '/');
  const padding: number = (4 - normalized.length % 4) % 4;
  let padded: string = normalized;
  for (let i = 0; i < padding; i++) {
    padded += '=';
  }
  const helper: util.Base64Helper = new util.Base64Helper();
  const bytes: Uint8Array = helper.decodeSync(padded, util.Type.BASIC);
  return bufferToString(bytes);
}

/** Base64 编码 UTF-8 文本 */
export function encodeBase64(value: string): string {
  const helper: util.Base64Helper = new util.Base64Helper();
  return helper.encodeToStringSync(new util.TextEncoder().encodeInto(value), util.Type.BASIC);
}

/** UTF-8 字节转字符串（不依赖 TextDecoder 的平台差异） */
export function bufferToString(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b0: number = bytes[i++];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
    } else if ((b0 & 0xE0) === 0xC0 && i < bytes.length) {
      const b1: number = bytes[i++];
      out += String.fromCharCode(((b0 & 0x1F) << 6) | (b1 & 0x3F));
    } else if ((b0 & 0xF0) === 0xE0 && i + 1 < bytes.length) {
      const b1: number = bytes[i++];
      const b2: number = bytes[i++];
      out += String.fromCharCode(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F));
    } else if ((b0 & 0xF8) === 0xF0 && i + 2 < bytes.length) {
      const b1: number = bytes[i++];
      const b2: number = bytes[i++];
      const b3: number = bytes[i++];
      let codePoint: number = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
      out += String.fromCodePoint(codePoint);
    }
  }
  return out;
}

export function safeDecodeURIComponent(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (e) {
    return value;
  }
}

/**
 * 稳定的节点 ID：对原始链接做双路 FNV-1a 32 位哈希，输出 16 位十六进制。
 * Android 版使用 MD5(rawLink)；两者都只要求同一链接稳定映射到同一 ID。
 */
export function hashId(link: string): string {
  let h1: number = 0x811C9DC5;
  let h2: number = 0x01000193;
  for (let i = 0; i < link.length; i++) {
    const c: number = link.charCodeAt(i);
    h1 = (h1 ^ c) >>> 0;
    h1 = Math.imul(h1, 0x01000193) >>> 0;
    h2 = (h2 + c) >>> 0;
    h2 = Math.imul(h2 ^ (h2 >>> 13), 0x85EBCA6B) >>> 0;
  }
  const hex = (n: number): string => {
    let s: string = (n >>> 0).toString(16);
    while (s.length < 8) {
      s = '0' + s;
    }
    return s;
  };
  return hex(h1) + hex(h2);
}

export function nowMs(): number {
  return new Date().getTime();
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const units: string[] = ['KB', 'MB', 'GB', 'TB'];
  let value: number = bytes;
  let unit: number = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value = value / 1024;
    unit++;
  }
  return `${value.toFixed(2)} ${units[unit]}`;
}

export function formatSpeed(bytesPerSecond: number): string {
  return `${formatBytes(bytesPerSecond)}/s`;
}

export enum LogLevel {
  DEBUG = 'D',
  INFO = 'I',
  WARN = 'W',
  ERROR = 'E'
}

export class LogEntry {
  time: string = '';
  level: LogLevel = LogLevel.INFO;
  tag: string = '';
  message: string = '';

  constructor(level: LogLevel, tag: string, message: string) {
    this.level = level;
    this.tag = tag;
    this.message = message;
    const d: Date = new Date();
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    this.time = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    console.info(`[FireflyVPN][${tag}] ${message}`);
  }
}

/** 运行时日志缓冲（对应 Android 的 RuntimeLog） */
export class RuntimeLog {
  private static entries: LogEntry[] = [];
  private static listeners: Array<() => void> = [];

  static add(level: LogLevel, tag: string, message: string): void {
    RuntimeLog.entries.push(new LogEntry(level, tag, message));
    if (RuntimeLog.entries.length > AppConfig.LOG_BUFFER_SIZE) {
      RuntimeLog.entries.splice(0, RuntimeLog.entries.length - AppConfig.LOG_BUFFER_SIZE);
    }
    RuntimeLog.listeners.forEach((cb: () => void) => cb());
  }

  static info(tag: string, message: string): void {
    RuntimeLog.add(LogLevel.INFO, tag, message);
  }

  static warn(tag: string, message: string): void {
    RuntimeLog.add(LogLevel.WARN, tag, message);
  }

  static error(tag: string, message: string): void {
    RuntimeLog.add(LogLevel.ERROR, tag, message);
  }

  static debug(tag: string, message: string): void {
    RuntimeLog.add(LogLevel.DEBUG, tag, message);
  }

  static getEntries(): LogEntry[] {
    return RuntimeLog.entries;
  }

  static clear(): void {
    RuntimeLog.entries = [];
    RuntimeLog.listeners.forEach((cb: () => void) => cb());
  }

  static subscribe(cb: () => void): void {
    RuntimeLog.listeners.push(cb);
  }

  static unsubscribe(cb: () => void): void {
    RuntimeLog.listeners = RuntimeLog.listeners.filter((item: () => void) => item !== cb);
  }
}
