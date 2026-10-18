/**
 * sing-box 配置生成器
 *
 * 移植自 Android: util/SingBoxConfigGenerator.kt（保留协议参数与路由语义）。
 * 生成的是完整 sing-box 配置；TUN 入站的 fd 由原生内核在启动时注入。
 */
import {
  AppSettings,
  IPv6RoutingMode,
  Node,
  NodeType,
  TunStackMode
} from '../model/Models';
import { parseUri, queryParam, UriParts, queryParamEnabled } from '../util/LinkParser';
import { JsonWriter } from '../util/JsonWriter';
import { decodeBase64Compat, RuntimeLog } from '../util/Utils';
import { AppConfig } from '../common/AppConfig';

const TAG: string = 'ConfigGenerator';

interface VmessFields {
  id?: string;
  aid?: string;
  scy?: string;
  net?: string;
  type?: string;
  host?: string;
  path?: string;
  tls?: string;
  sni?: string;
  alpn?: string;
  fp?: string;
}

export class ConfigGenerator {
  /** 生成连接配置 */
  static generate(node: Node, settings: AppSettings): string {
    const w: JsonWriter = new JsonWriter();
    w.objectStart();
    w.key('log').objectStart().key('level').string('info').key('timestamp').bool(true).objectEnd();

    ConfigGenerator.writeDns(w, settings);
    ConfigGenerator.writeInbounds(w, settings);
    ConfigGenerator.writeOutbounds(w, node, settings);
    ConfigGenerator.writeRoute(w, settings);
    w.key('experimental').objectStart()
      .key('clash_api').objectStart()
      .key('external_controller').string(`127.0.0.1:${AppConfig.CLASH_API_PORT}`)
      .key('default_mode').string('rule')
      .objectEnd()
      .objectEnd();

    w.objectEnd();
    return w.toString();
  }

  private static ipv6Enabled(mode: IPv6RoutingMode): boolean {
    return mode === IPv6RoutingMode.ENABLED || mode === IPv6RoutingMode.PREFER || mode === IPv6RoutingMode.ONLY;
  }

  private static dnsStrategy(mode: IPv6RoutingMode): string {
    if (mode === IPv6RoutingMode.PREFER) {
      return 'prefer_ipv6';
    }
    if (mode === IPv6RoutingMode.ONLY) {
      return 'ipv6_only';
    }
    return 'prefer_ipv4';
  }

  private static writeDns(w: JsonWriter, settings: AppSettings): void {
    w.key('dns').objectStart();
    w.key('servers').arrayStart();
    w.objectStart()
      .key('tag').string('dns-proxy')
      .key('address').string('https://1.1.1.1/dns-query')
      .key('detour').string('proxy')
      .objectEnd();
    w.objectStart()
      .key('tag').string('dns-direct')
      .key('address').string(AppConfig.VPN_DNS_CHINA)
      .key('detour').string('direct')
      .objectEnd();
    w.arrayEnd();
    w.key('final').string('dns-proxy');
    w.key('strategy').string(ConfigGenerator.dnsStrategy(settings.ipv6Mode));
    w.objectEnd();
  }

  private static writeInbounds(w: JsonWriter, settings: AppSettings): void {
    w.key('inbounds').arrayStart();
    w.objectStart();
    w.key('type').string('tun');
    w.key('tag').string('tun-in');
    w.key('address').arrayStart()
      .string(`${AppConfig.VPN_IPV4_ADDRESS}/30`);
    if (ConfigGenerator.ipv6Enabled(settings.ipv6Mode)) {
      w.string(`${AppConfig.VPN_IPV6_ADDRESS}/126`);
    }
    w.arrayEnd();
    w.key('mtu').number(AppConfig.VPN_MTU);
    w.key('auto_route').bool(true);
    w.key('strict_route').bool(false);
    w.key('stack').string(settings.tunStackMode as string);
    w.key('sniff').bool(true);
    w.key('sniff_override_destination').bool(false);
    w.objectEnd();
    w.arrayEnd();
  }

  private static writeOutbounds(w: JsonWriter, node: Node, settings: AppSettings): void {
    w.key('outbounds').arrayStart();
    ConfigGenerator.writeNodeOutbound(w, node);
    w.objectStart().key('type').string('direct').key('tag').string('direct').objectEnd();
    w.objectStart().key('type').string('block').key('tag').string('block').objectEnd();
    w.arrayEnd();
  }

  private static writeRoute(w: JsonWriter, settings: AppSettings): void {
    w.key('route').objectStart();
    // 鸿蒙扩展进程通过 VpnConnection.protectProcessNet() 绕过 VPN，
    // 因此不需要 auto_detect_interface，也避免了 OHOS 上 netlink 监控失败的风险。
    w.key('auto_detect_interface').bool(false);
    w.key('final').string('proxy');
    w.key('rules').arrayStart();
    // 私有地址直连
    w.objectStart()
      .key('ip_is_private').bool(true)
      .key('outbound').string('direct')
      .objectEnd();
    w.arrayEnd();
    w.objectEnd();
  }

  private static writeNodeOutbound(w: JsonWriter, node: Node): void {
    const uri: UriParts | null = parseUri(node.rawLink);
    if (uri === null) {
      throw new Error(`无法解析节点链接: ${node.name}`);
    }
    switch (node.type) {
      case NodeType.VLESS:
        ConfigGenerator.writeVless(w, node, uri);
        break;
      case NodeType.VMESS:
        ConfigGenerator.writeVmess(w, node, uri);
        break;
      case NodeType.TROJAN:
        ConfigGenerator.writeTrojan(w, node, uri);
        break;
      case NodeType.HYSTERIA2:
        ConfigGenerator.writeHysteria2(w, node, uri);
        break;
      case NodeType.SHADOWSOCKS:
        ConfigGenerator.writeShadowsocks(w, node, uri);
        break;
      case NodeType.SOCKS:
        ConfigGenerator.writeSocks(w, node, uri);
        break;
      case NodeType.HTTP:
        ConfigGenerator.writeHttp(w, node, uri);
        break;
      case NodeType.ANYTLS:
        ConfigGenerator.writeAnyTls(w, node, uri);
        break;
      case NodeType.TUIC:
        ConfigGenerator.writeTuic(w, node, uri);
        break;
      default:
        throw new Error(`暂不支持的节点协议: ${node.type}`);
    }
  }

  private static startOutbound(w: JsonWriter, type: string): void {
    w.objectStart();
    w.key('type').string(type);
    w.key('tag').string('proxy');
    w.key('server').string('');
  }

  private static writeTls(w: JsonWriter, uri: UriParts, defaultSni: string, forceTls: boolean): void {
    const security: string = queryParam(uri, ['security']).toLowerCase();
    const tlsEnabled: boolean = forceTls || security === 'tls' || security === 'reality' || security === 'xtls';
    if (!tlsEnabled) {
      return;
    }
    w.key('tls').objectStart();
    w.key('enabled').bool(true);
    const sni: string = queryParam(uri, ['sni', 'peer', 'servername']);
    w.key('server_name').string(sni.length > 0 ? sni : defaultSni);
    const insecure: string = queryParam(uri, ['allowInsecure', 'insecure', 'skip-cert-verify']);
    w.key('insecure').bool(insecure === '1' || insecure.toLowerCase() === 'true');
    const alpn: string = queryParam(uri, ['alpn']);
    if (alpn.length > 0) {
      w.key('alpn').arrayStart();
      for (const item of alpn.split(',')) {
        w.string(item.trim());
      }
      w.arrayEnd();
    }
    const fingerprint: string = queryParam(uri, ['fp', 'fingerprint']);
    if (fingerprint.length > 0) {
      w.key('utls').objectStart().key('enabled').bool(true).key('fingerprint').string(fingerprint).objectEnd();
    }
    if (security === 'reality') {
      w.key('reality').objectStart()
        .key('enabled').bool(true)
        .key('public_key').string(queryParam(uri, ['pbk', 'public_key']))
        .key('short_id').string(queryParam(uri, ['sid', 'short_id']))
        .objectEnd();
    }
    w.objectEnd();
  }

  private static writeTransport(w: JsonWriter, uri: UriParts, defaultType: string): void {
    const type: string = (queryParam(uri, ['type', 'net']) || defaultType).toLowerCase();
    if (type.length === 0 || type === 'tcp' || type === 'none') {
      return;
    }
    w.key('transport').objectStart();
    w.key('type').string(type === 'h2' ? 'http' : type);
    if (type === 'ws') {
      const path: string = queryParam(uri, ['path']);
      if (path.length > 0) {
        w.key('path').string(path);
      }
      const host: string = queryParam(uri, ['host']);
      if (host.length > 0) {
        w.key('headers').objectStart().key('Host').string(host).objectEnd();
      }
    } else if (type === 'grpc') {
      const serviceName: string = queryParam(uri, ['serviceName', 'service_name']);
      if (serviceName.length > 0) {
        w.key('service_name').string(serviceName);
      }
    } else if (type === 'http' || type === 'h2') {
      const path: string = queryParam(uri, ['path']);
      const host: string = queryParam(uri, ['host']);
      if (host.length > 0) {
        w.key('host').arrayStart().string(host).arrayEnd();
      }
      if (path.length > 0) {
        w.key('path').string(path);
      }
    }
    w.objectEnd();
  }

  private static writeVless(w: JsonWriter, node: Node, uri: UriParts): void {
    w.objectStart();
    w.key('type').string('vless');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    w.key('uuid').string(uri.username);
    const flow: string = queryParam(uri, ['flow']);
    if (flow.length > 0) {
      w.key('flow').string(flow);
    }
    w.key('packet_encoding').string('xudp');
    ConfigGenerator.writeTls(w, uri, node.server, false);
    ConfigGenerator.writeTransport(w, uri, 'tcp');
    w.objectEnd();
  }

  private static writeVmess(w: JsonWriter, node: Node, uri: UriParts): void {
    let fields: VmessFields = {};
    try {
      const json: string = decodeBase64Compat(node.rawLink.substring('vmess://'.length));
      fields = JSON.parse(json) as VmessFields;
    } catch (e) {
      RuntimeLog.warn(TAG, 'VMess 配置解析失败，使用链接中的默认值');
    }
    w.objectStart();
    w.key('type').string('vmess');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    w.key('uuid').string(fields.id !== undefined ? fields.id : uri.username);
    w.key('security').string(fields.scy !== undefined && fields.scy.length > 0 ? fields.scy : 'auto');
    w.key('alter_id').number(fields.aid !== undefined ? parseInt(fields.aid, 10) : 0);
    const tls: string = fields.tls !== undefined ? fields.tls : '';
    if (tls === 'tls') {
      w.key('tls').objectStart().key('enabled').bool(true)
        .key('server_name').string(fields.sni !== undefined ? fields.sni : node.server)
        .objectEnd();
    }
    const network: string = fields.net !== undefined ? fields.net : 'tcp';
    if (network === 'ws') {
      w.key('transport').objectStart().key('type').string('ws');
      if (fields.path !== undefined && fields.path.length > 0) {
        w.key('path').string(fields.path);
      }
      if (fields.host !== undefined && fields.host.length > 0) {
        w.key('headers').objectStart().key('Host').string(fields.host).objectEnd();
      }
      w.objectEnd();
    } else if (network === 'grpc') {
      w.key('transport').objectStart().key('type').string('grpc');
      if (fields.path !== undefined && fields.path.length > 0) {
        w.key('service_name').string(fields.path);
      }
      w.objectEnd();
    }
    w.objectEnd();
  }

  private static writeTrojan(w: JsonWriter, node: Node, uri: UriParts): void {
    w.objectStart();
    w.key('type').string('trojan');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    w.key('password').string(uri.username.length > 0 ? uri.username : uri.password);
    ConfigGenerator.writeTls(w, uri, node.server, true);
    ConfigGenerator.writeTransport(w, uri, 'tcp');
    w.objectEnd();
  }

  private static writeHysteria2(w: JsonWriter, node: Node, uri: UriParts): void {
    w.objectStart();
    w.key('type').string('hysteria2');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    w.key('password').string(uri.username.length > 0 ? uri.username : uri.password);
    const obfs: string = queryParam(uri, ['obfs']);
    if (obfs.length > 0 && obfs !== 'none') {
      w.key('obfs').objectStart()
        .key('type').string(obfs)
        .key('password').string(queryParam(uri, ['obfs-password', 'obfs_password']))
        .objectEnd();
    }
    const up: string = queryParam(uri, ['up', 'upmbps']);
    const down: string = queryParam(uri, ['down', 'downmbps']);
    if (down.length > 0) {
      w.key('down_mbps').number(parseFloat(down.replace(/[^0-9.]/g, '')) || 0);
    }
    if (up.length > 0) {
      w.key('up_mbps').number(parseFloat(up.replace(/[^0-9.]/g, '')) || 0);
    }
    ConfigGenerator.writeTls(w, uri, node.server, true);
    w.objectEnd();
  }

  private static writeShadowsocks(w: JsonWriter, node: Node, uri: UriParts): void {
    let method: string = '';
    let password: string = '';
    if (uri.username.indexOf(':') >= 0) {
      const decoded: string = decodeBase64Compat(uri.username);
      const colon: number = decoded.indexOf(':');
      method = colon >= 0 ? decoded.substring(0, colon) : decoded;
      password = colon >= 0 ? decoded.substring(colon + 1) : '';
    } else if (uri.username.length > 0) {
      // ss://base64(method:password)@host:port
      try {
        const decoded: string = decodeBase64Compat(uri.username);
        const colon: number = decoded.indexOf(':');
        if (colon > 0) {
          method = decoded.substring(0, colon);
          password = decoded.substring(colon + 1);
        }
      } catch (e) {
        method = 'aes-256-gcm';
        password = uri.username;
      }
    }
    w.objectStart();
    w.key('type').string('shadowsocks');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    w.key('method').string(method.length > 0 ? method : 'aes-256-gcm');
    w.key('password').string(password);
    w.objectEnd();
  }

  private static writeSocks(w: JsonWriter, node: Node, uri: UriParts): void {
    w.objectStart();
    w.key('type').string('socks');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    const version: string = node.rawLink.toLowerCase().indexOf('socks4') >= 0 ? '4' : '5';
    w.key('version').string(version);
    if (uri.username.length > 0) {
      w.key('username').string(uri.username);
      w.key('password').string(uri.password);
    }
    w.objectEnd();
  }

  private static writeHttp(w: JsonWriter, node: Node, uri: UriParts): void {
    w.objectStart();
    w.key('type').string('http');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    if (uri.username.length > 0) {
      w.key('username').string(uri.username);
      w.key('password').string(uri.password);
    }
    if (node.rawLink.toLowerCase().startsWith('https://')) {
      ConfigGenerator.writeTls(w, uri, node.server, true);
    }
    w.objectEnd();
  }

  private static writeAnyTls(w: JsonWriter, node: Node, uri: UriParts): void {
    w.objectStart();
    w.key('type').string('anytls');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    w.key('password').string(uri.username.length > 0 ? uri.username : uri.password);
    ConfigGenerator.writeTls(w, uri, node.server, true);
    w.objectEnd();
  }

  private static writeTuic(w: JsonWriter, node: Node, uri: UriParts): void {
    w.objectStart();
    w.key('type').string('tuic');
    w.key('tag').string('proxy');
    w.key('server').string(node.server);
    w.key('server_port').number(node.port);
    w.key('uuid').string(uri.username);
    w.key('password').string(uri.password);
    const congestion: string = queryParam(uri, ['congestion_control', 'congestion']);
    w.key('congestion_control').string(congestion.length > 0 ? congestion : 'bbr');
    const relayMode: string = queryParam(uri, ['udp_relay_mode']);
    if (relayMode.length > 0) {
      w.key('udp_relay_mode').string(relayMode);
    }
    ConfigGenerator.writeTls(w, uri, node.server, true);
    w.objectEnd();
  }
}

/** 由 EntryAbility 注入 bundleName，供路由规则使用 */
export class AppContextBundleNameHolder {
  private static bundle: string = 'io.github.iskongkongyo.fireflyvpn';

  static setBundleName(bundleName: string): void {
    AppContextBundleNameHolder.bundle = bundleName;
  }

  static bundleName(): string {
    return AppContextBundleNameHolder.bundle;
  }
}
