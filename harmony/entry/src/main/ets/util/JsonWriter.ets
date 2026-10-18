/**
 * 轻量 JSON 构建器：用于生成 sing-box 配置，避免大量动态对象在 ArkTS 中的类型限制。
 */
export class JsonWriter {
  private buffer: string = '';
  private stack: boolean[] = []; // true = 需要在该层级插入逗号

  private beforeValue(): void {
    if (this.stack.length > 0 && this.stack[this.stack.length - 1]) {
      this.buffer += ',';
    }
    if (this.stack.length > 0) {
      this.stack[this.stack.length - 1] = true;
    }
  }

  objectStart(): JsonWriter {
    this.beforeValue();
    this.buffer += '{';
    this.stack.push(false);
    return this;
  }

  objectEnd(): JsonWriter {
    this.stack.pop();
    this.buffer += '}';
    return this;
  }

  arrayStart(): JsonWriter {
    this.beforeValue();
    this.buffer += '[';
    this.stack.push(false);
    return this;
  }

  arrayEnd(): JsonWriter {
    this.stack.pop();
    this.buffer += ']';
    return this;
  }

  key(name: string): JsonWriter {
    if (this.stack.length > 0 && this.stack[this.stack.length - 1]) {
      this.buffer += ',';
    }
    this.buffer += `${JSON.stringify(name)}:`;
    return this;
  }

  string(value: string): JsonWriter {
    this.beforeValue();
    this.buffer += JSON.stringify(value);
    return this;
  }

  number(value: number): JsonWriter {
    this.beforeValue();
    this.buffer += `${value}`;
    return this;
  }

  bool(value: boolean): JsonWriter {
    this.beforeValue();
    this.buffer += value ? 'true' : 'false';
    return this;
  }

  nullValue(): JsonWriter {
    this.beforeValue();
    this.buffer += 'null';
    return this;
  }

  /** 写入已构造好的原始 JSON 片段 */
  raw(value: string): JsonWriter {
    this.beforeValue();
    this.buffer += value;
    return this;
  }

  toString(): string {
    return this.buffer;
  }
}
