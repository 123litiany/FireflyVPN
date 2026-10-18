/**
 * 本地数据库（Room → relationalStore）
 *
 * Android 版使用 Room + SQLCipher；鸿蒙版使用 relationalStore 并开启数据库加密，
 * 表结构与字段语义保持一致，便于后续同步与迁移。
 */
import relationalStore from '@ohos.data.relationalStore';
import { common } from '@kit.AbilityKit';
import { AppConfig } from '../common/AppConfig';
import {
  BandwidthTestStatus,
  Node,
  NodeSource,
  NodeType,
  SubscriptionGroup,
  SubscriptionGroupSummary,
  SubscriptionLink
} from '../model/Models';
import { nowMs, RuntimeLog } from '../util/Utils';

const TAG: string = 'Database';

const SQL_CREATE_NODES: string = `
CREATE TABLE IF NOT EXISTS nodes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  server TEXT NOT NULL,
  port INTEGER NOT NULL,
  rawLink TEXT NOT NULL,
  country TEXT NOT NULL DEFAULT '',
  countryName TEXT NOT NULL DEFAULT '',
  latency INTEGER NOT NULL DEFAULT -1,
  isAvailable INTEGER NOT NULL DEFAULT 1,
  lastTestedAt INTEGER NOT NULL DEFAULT 0,
  sortOrder INTEGER NOT NULL DEFAULT 0,
  downloadMbps REAL NOT NULL DEFAULT 0,
  uploadMbps REAL NOT NULL DEFAULT 0,
  downloadTestStatus INTEGER NOT NULL DEFAULT 0,
  uploadTestStatus INTEGER NOT NULL DEFAULT 0,
  downloadTestMessage TEXT NOT NULL DEFAULT '',
  uploadTestMessage TEXT NOT NULL DEFAULT '',
  unlockSummary TEXT NOT NULL DEFAULT '',
  unlockPassed INTEGER NOT NULL DEFAULT 0,
  autoTestStatus TEXT NOT NULL DEFAULT '',
  autoTestedAt INTEGER NOT NULL DEFAULT 0,
  source INTEGER NOT NULL DEFAULT 0,
  subscriptionGroupId TEXT NOT NULL DEFAULT '',
  favoriteSourceNodeId TEXT NOT NULL DEFAULT '',
  favoriteCreatedAt INTEGER NOT NULL DEFAULT 0
)`;

const SQL_CREATE_GROUPS: string = `
CREATE TABLE IF NOT EXISTS subscription_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  autoUpdateEnabled INTEGER NOT NULL DEFAULT 0,
  updateIntervalMinutes INTEGER NOT NULL DEFAULT 0,
  deduplicateEnabled INTEGER NOT NULL DEFAULT 1,
  userAgent TEXT NOT NULL DEFAULT '',
  lastUpdatedAt INTEGER NOT NULL DEFAULT 0,
  lastError TEXT NOT NULL DEFAULT '',
  lastNodeCount INTEGER NOT NULL DEFAULT 0,
  sortOrder INTEGER NOT NULL DEFAULT 0,
  createdAt INTEGER NOT NULL DEFAULT 0
)`;

const SQL_CREATE_LINKS: string = `
CREATE TABLE IF NOT EXISTS subscription_links (
  id TEXT PRIMARY KEY,
  groupId TEXT NOT NULL,
  url TEXT NOT NULL,
  sortOrder INTEGER NOT NULL DEFAULT 0
)`;

const NODE_COLUMNS: string[] = [
  'id', 'name', 'type', 'server', 'port', 'rawLink', 'country', 'countryName', 'latency',
  'isAvailable', 'lastTestedAt', 'sortOrder', 'downloadMbps', 'uploadMbps',
  'downloadTestStatus', 'uploadTestStatus', 'downloadTestMessage', 'uploadTestMessage',
  'unlockSummary', 'unlockPassed', 'autoTestStatus', 'autoTestedAt', 'source',
  'subscriptionGroupId', 'favoriteSourceNodeId', 'favoriteCreatedAt'
];

export class Database {
  private static store: relationalStore.RdbStore | null = null;

  static isReady(): boolean {
    return Database.store !== null;
  }

  static async init(context: common.Context): Promise<void> {
    if (Database.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: AppConfig.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
      encrypt: true
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await store.executeSql(SQL_CREATE_NODES);
    await store.executeSql(SQL_CREATE_GROUPS);
    await store.executeSql(SQL_CREATE_LINKS);
    Database.store = store;
    RuntimeLog.info(TAG, '数据库已打开（加密存储）');
  }

  private static requireStore(): relationalStore.RdbStore {
    if (Database.store === null) {
      throw new Error('数据库尚未初始化');
    }
    return Database.store;
  }

  private static nodeToBucket(node: Node): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': node.id,
      'name': node.name,
      'type': node.type as string,
      'server': node.server,
      'port': node.port,
      'rawLink': node.rawLink,
      'country': node.country,
      'countryName': node.countryName,
      'latency': node.latency,
      'isAvailable': node.isAvailable ? 1 : 0,
      'lastTestedAt': node.lastTestedAt,
      'sortOrder': node.sortOrder,
      'downloadMbps': node.downloadMbps,
      'uploadMbps': node.uploadMbps,
      'downloadTestStatus': node.downloadTestStatus as number,
      'uploadTestStatus': node.uploadTestStatus as number,
      'downloadTestMessage': node.downloadTestMessage,
      'uploadTestMessage': node.uploadTestMessage,
      'unlockSummary': node.unlockSummary,
      'unlockPassed': node.unlockPassed ? 1 : 0,
      'autoTestStatus': node.autoTestStatus,
      'autoTestedAt': node.autoTestedAt,
      'source': node.source as number,
      'subscriptionGroupId': node.subscriptionGroupId,
      'favoriteSourceNodeId': node.favoriteSourceNodeId,
      'favoriteCreatedAt': node.favoriteCreatedAt
    };
    return bucket;
  }

  private static bucketToNode(resultSet: relationalStore.ResultSet): Node {
    const node: Node = new Node();
    node.id = resultSet.getString(resultSet.getColumnIndex('id'));
    node.name = resultSet.getString(resultSet.getColumnIndex('name'));
    node.type = Database.parseNodeType(resultSet.getString(resultSet.getColumnIndex('type')));
    node.server = resultSet.getString(resultSet.getColumnIndex('server'));
    node.port = resultSet.getLong(resultSet.getColumnIndex('port'));
    node.rawLink = resultSet.getString(resultSet.getColumnIndex('rawLink'));
    node.country = resultSet.getString(resultSet.getColumnIndex('country'));
    node.countryName = resultSet.getString(resultSet.getColumnIndex('countryName'));
    node.latency = resultSet.getLong(resultSet.getColumnIndex('latency'));
    node.isAvailable = resultSet.getLong(resultSet.getColumnIndex('isAvailable')) === 1;
    node.lastTestedAt = resultSet.getLong(resultSet.getColumnIndex('lastTestedAt'));
    node.sortOrder = resultSet.getLong(resultSet.getColumnIndex('sortOrder'));
    node.downloadMbps = resultSet.getDouble(resultSet.getColumnIndex('downloadMbps'));
    node.uploadMbps = resultSet.getDouble(resultSet.getColumnIndex('uploadMbps'));
    node.downloadTestStatus = resultSet.getLong(resultSet.getColumnIndex('downloadTestStatus')) as BandwidthTestStatus;
    node.uploadTestStatus = resultSet.getLong(resultSet.getColumnIndex('uploadTestStatus')) as BandwidthTestStatus;
    node.downloadTestMessage = resultSet.getString(resultSet.getColumnIndex('downloadTestMessage'));
    node.uploadTestMessage = resultSet.getString(resultSet.getColumnIndex('uploadTestMessage'));
    node.unlockSummary = resultSet.getString(resultSet.getColumnIndex('unlockSummary'));
    node.unlockPassed = resultSet.getLong(resultSet.getColumnIndex('unlockPassed')) === 1;
    node.autoTestStatus = resultSet.getString(resultSet.getColumnIndex('autoTestStatus'));
    node.autoTestedAt = resultSet.getLong(resultSet.getColumnIndex('autoTestedAt'));
    node.source = resultSet.getLong(resultSet.getColumnIndex('source')) as NodeSource;
    node.subscriptionGroupId = resultSet.getString(resultSet.getColumnIndex('subscriptionGroupId'));
    node.favoriteSourceNodeId = resultSet.getString(resultSet.getColumnIndex('favoriteSourceNodeId'));
    node.favoriteCreatedAt = resultSet.getLong(resultSet.getColumnIndex('favoriteCreatedAt'));
    return node;
  }

  private static parseNodeType(value: string): NodeType {
    const all: NodeType[] = [
      NodeType.VLESS, NodeType.VMESS, NodeType.TROJAN, NodeType.HYSTERIA2, NodeType.ANYTLS,
      NodeType.TUIC, NodeType.NAIVE, NodeType.WIREGUARD, NodeType.SHADOWSOCKS, NodeType.SOCKS,
      NodeType.HTTP
    ];
    for (const type of all) {
      if (type as string === value) {
        return type;
      }
    }
    return NodeType.UNKNOWN;
  }

  /** 读取节点：groupId 为空表示全部 */
  static async loadNodes(groupId?: string): Promise<Node[]> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('nodes');
    if (groupId !== undefined && groupId.length > 0) {
      predicates.equalTo('subscriptionGroupId', groupId);
    }
    predicates.orderByAsc('sortOrder');
    const resultSet: relationalStore.ResultSet = await store.query(predicates, NODE_COLUMNS);
    const nodes: Node[] = [];
    try {
      while (resultSet.goToNextRow()) {
        nodes.push(Database.bucketToNode(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return nodes;
  }

  /** 用新解析结果替换某个订阅分组的节点（保留收藏节点） */
  static async replaceGroupNodes(groupId: string, nodes: Node[]): Promise<void> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('nodes');
    predicates.equalTo('subscriptionGroupId', groupId);
    predicates.equalTo('source', NodeSource.SUBSCRIPTION as number);
    await store.delete(predicates);

    const buckets: relationalStore.ValuesBucket[] = [];
    for (let i = 0; i < nodes.length; i++) {
      const node: Node = nodes[i];
      node.subscriptionGroupId = groupId;
      node.source = NodeSource.SUBSCRIPTION;
      node.sortOrder = i;
      buckets.push(Database.nodeToBucket(node));
    }
    if (buckets.length > 0) {
      await store.batchInsert('nodes', buckets);
    }
    RuntimeLog.info(TAG, `分组 ${groupId} 写入 ${buckets.length} 个节点`);
  }

  static async upsertNode(node: Node): Promise<void> {
    const store: relationalStore.RdbStore = Database.requireStore();
    await store.insert('nodes', Database.nodeToBucket(node),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  static async updateNodeTestResult(node: Node): Promise<void> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('nodes');
    predicates.equalTo('id', node.id);
    const bucket: relationalStore.ValuesBucket = {
      'latency': node.latency,
      'isAvailable': node.isAvailable ? 1 : 0,
      'lastTestedAt': node.lastTestedAt,
      'autoTestStatus': node.autoTestStatus,
      'autoTestedAt': node.autoTestedAt,
      'downloadMbps': node.downloadMbps,
      'uploadMbps': node.uploadMbps,
      'downloadTestStatus': node.downloadTestStatus as number,
      'uploadTestStatus': node.uploadTestStatus as number,
      'downloadTestMessage': node.downloadTestMessage,
      'uploadTestMessage': node.uploadTestMessage,
      'unlockSummary': node.unlockSummary,
      'unlockPassed': node.unlockPassed ? 1 : 0
    };
    await store.update(bucket, predicates);
  }

  static async deleteGroupNodes(groupId: string): Promise<void> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('nodes');
    predicates.equalTo('subscriptionGroupId', groupId);
    await store.delete(predicates);
  }

  static async loadGroups(): Promise<SubscriptionGroupSummary[]> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subscription_groups');
    predicates.orderByAsc('sortOrder');
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const groups: SubscriptionGroupSummary[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const group: SubscriptionGroup = new SubscriptionGroup();
        group.id = resultSet.getString(resultSet.getColumnIndex('id'));
        group.name = resultSet.getString(resultSet.getColumnIndex('name'));
        group.autoUpdateEnabled = resultSet.getLong(resultSet.getColumnIndex('autoUpdateEnabled')) === 1;
        group.updateIntervalMinutes = resultSet.getLong(resultSet.getColumnIndex('updateIntervalMinutes'));
        group.deduplicateEnabled = resultSet.getLong(resultSet.getColumnIndex('deduplicateEnabled')) === 1;
        group.userAgent = resultSet.getString(resultSet.getColumnIndex('userAgent'));
        group.lastUpdatedAt = resultSet.getLong(resultSet.getColumnIndex('lastUpdatedAt'));
        group.lastError = resultSet.getString(resultSet.getColumnIndex('lastError'));
        group.lastNodeCount = resultSet.getLong(resultSet.getColumnIndex('lastNodeCount'));
        group.sortOrder = resultSet.getLong(resultSet.getColumnIndex('sortOrder'));
        group.createdAt = resultSet.getLong(resultSet.getColumnIndex('createdAt'));
        const summary: SubscriptionGroupSummary = new SubscriptionGroupSummary();
        summary.group = group;
        summary.links = await Database.loadLinks(group.id);
        groups.push(summary);
      }
    } finally {
      resultSet.close();
    }
    return groups;
  }

  static async loadLinks(groupId: string): Promise<SubscriptionLink[]> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subscription_links');
    predicates.equalTo('groupId', groupId);
    predicates.orderByAsc('sortOrder');
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const links: SubscriptionLink[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const link: SubscriptionLink = new SubscriptionLink();
        link.id = resultSet.getString(resultSet.getColumnIndex('id'));
        link.groupId = resultSet.getString(resultSet.getColumnIndex('groupId'));
        link.url = resultSet.getString(resultSet.getColumnIndex('url'));
        link.sortOrder = resultSet.getLong(resultSet.getColumnIndex('sortOrder'));
        links.push(link);
      }
    } finally {
      resultSet.close();
    }
    return links;
  }

  static async saveGroup(summary: SubscriptionGroupSummary): Promise<void> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const group: SubscriptionGroup = summary.group;
    if (group.createdAt === 0) {
      group.createdAt = nowMs();
    }
    const bucket: relationalStore.ValuesBucket = {
      'id': group.id,
      'name': group.name,
      'autoUpdateEnabled': group.autoUpdateEnabled ? 1 : 0,
      'updateIntervalMinutes': group.updateIntervalMinutes,
      'deduplicateEnabled': group.deduplicateEnabled ? 1 : 0,
      'userAgent': group.userAgent,
      'lastUpdatedAt': group.lastUpdatedAt,
      'lastError': group.lastError,
      'lastNodeCount': group.lastNodeCount,
      'sortOrder': group.sortOrder,
      'createdAt': group.createdAt
    };
    await store.insert('subscription_groups', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

    const delPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subscription_links');
    delPredicates.equalTo('groupId', group.id);
    await store.delete(delPredicates);
    for (let i = 0; i < summary.links.length; i++) {
      const link: SubscriptionLink = summary.links[i];
      link.groupId = group.id;
      link.sortOrder = i;
      const linkBucket: relationalStore.ValuesBucket = {
        'id': link.id,
        'groupId': link.groupId,
        'url': link.url,
        'sortOrder': link.sortOrder
      };
      await store.insert('subscription_links', linkBucket,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  static async deleteGroup(groupId: string): Promise<void> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const groupPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subscription_groups');
    groupPredicates.equalTo('id', groupId);
    await store.delete(groupPredicates);
    const linkPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('subscription_links');
    linkPredicates.equalTo('groupId', groupId);
    await store.delete(linkPredicates);
    await Database.deleteGroupNodes(groupId);
  }

  static async countNodes(groupId: string): Promise<number> {
    const store: relationalStore.RdbStore = Database.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('nodes');
    predicates.equalTo('subscriptionGroupId', groupId);
    const resultSet: relationalStore.ResultSet = await store.query(predicates, ['id']);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  }
}
