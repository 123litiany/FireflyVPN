/**
 * 订阅仓库：拉取、解析、去重并落库
 *
 * 移植自 Android: network/SubscriptionParser + viewmodel 的订阅管理逻辑。
 */
import { AppConfig } from '../common/AppConfig';
import {
  DEFAULT_SUBSCRIPTION_GROUP_ID,
  Node,
  SubscriptionGroup,
  SubscriptionGroupSummary,
  SubscriptionLink
} from '../model/Models';
import { Database } from '../data/Database';
import { LinkParser } from '../util/LinkParser';
import { hashId, nowMs, RuntimeLog } from '../util/Utils';
import { HttpClient } from '../net/HttpClient';

const TAG: string = 'SubscriptionRepo';

export class SubscriptionRepository {
  /** 创建默认分组（首次启动时） */
  static async ensureDefaultGroup(): Promise<SubscriptionGroupSummary> {
    const groups: SubscriptionGroupSummary[] = await Database.loadGroups();
    if (groups.length > 0) {
      return groups[0];
    }
    const summary: SubscriptionGroupSummary = new SubscriptionGroupSummary();
    summary.group = new SubscriptionGroup();
    summary.group.id = DEFAULT_SUBSCRIPTION_GROUP_ID;
    summary.group.name = '默认订阅';
    summary.group.sortOrder = 0;
    summary.group.createdAt = nowMs();
    summary.links = [];
    await Database.saveGroup(summary);
    RuntimeLog.info(TAG, `已创建默认订阅分组 ${summary.group.id}`);
    return summary;
  }

  static async listGroups(): Promise<SubscriptionGroupSummary[]> {
    return Database.loadGroups();
  }

  /** 新增分组并拉取订阅 */
  static async addGroup(name: string, urls: string[]): Promise<SubscriptionGroupSummary> {
    const summary: SubscriptionGroupSummary = new SubscriptionGroupSummary();
    const group: SubscriptionGroup = new SubscriptionGroup();
    group.id = `group_${hashId(`${name}_${nowMs()}_${Math.random()}`)}`;
    group.name = name.length > 0 ? name : '订阅分组';
    group.createdAt = nowMs();
    group.autoUpdateEnabled = true;
    summary.group = group;
    summary.links = [];
    for (let i = 0; i < urls.length; i++) {
      const url: string = urls[i].trim();
      if (url.length === 0) {
        continue;
      }
      const link: SubscriptionLink = new SubscriptionLink();
      link.id = `link_${hashId(`${group.id}_${url}`)}`;
      link.groupId = group.id;
      link.url = url;
      link.sortOrder = i;
      summary.links.push(link);
    }
    await Database.saveGroup(summary);
    await SubscriptionRepository.refreshGroup(group.id);
    return summary;
  }

  /** 更新指定分组：逐条链接拉取、解析、合并、去重 */
  static async refreshGroup(groupId: string): Promise<void> {
    const groups: SubscriptionGroupSummary[] = await Database.loadGroups();
    let target: SubscriptionGroupSummary | null = null;
    for (const summary of groups) {
      if (summary.group.id === groupId) {
        target = summary;
        break;
      }
    }
    if (target === null) {
      throw new Error(`订阅分组不存在: ${groupId}`);
    }
    const allNodes: Node[] = [];
    const errors: string[] = [];
    for (const link of target.links) {
      try {
        const content: string = await HttpClient.fetchText(link.url,
          target.group.userAgent.length > 0 ? target.group.userAgent : AppConfig.USER_AGENT,
          AppConfig.NODE_REQUEST_TIMEOUT_MS);
        const nodes: Node[] = LinkParser.parseSubscription(content);
        if (nodes.length === 0) {
          errors.push(`${link.url}: 未解析到节点`);
        }
        allNodes.push(...nodes);
      } catch (e) {
        errors.push(`${link.url}: ${JSON.stringify(e)}`);
        RuntimeLog.error(TAG, `订阅拉取失败 ${link.url}: ${JSON.stringify(e)}`);
      }
    }
    const finalNodes: Node[] = target.group.deduplicateEnabled
      ? LinkParser.deduplicate(allNodes)
      : allNodes;
    for (let i = 0; i < finalNodes.length; i++) {
      finalNodes[i].sortOrder = i;
      finalNodes[i].subscriptionGroupId = groupId;
    }
    await Database.replaceGroupNodes(groupId, finalNodes);
    target.group.lastUpdatedAt = nowMs();
    target.group.lastNodeCount = finalNodes.length;
    target.group.lastError = errors.join('\n');
    await Database.saveGroup(target);
    RuntimeLog.info(TAG, `分组 ${target.group.name} 已更新：${finalNodes.length} 个节点，${errors.length} 个错误`);
  }

  /** 启动时按策略自动更新（仅更新启用了自动更新的分组） */
  static async autoUpdateIfDue(): Promise<void> {
    const groups: SubscriptionGroupSummary[] = await Database.loadGroups();
    const now: number = nowMs();
    for (const summary of groups) {
      const group: SubscriptionGroup = summary.group;
      if (!group.autoUpdateEnabled || group.lastUpdatedAt === 0) {
        continue;
      }
      const interval: number = group.updateIntervalMinutes;
      if (interval > 0 && now - group.lastUpdatedAt < interval * 60000) {
        continue;
      }
      try {
        await SubscriptionRepository.refreshGroup(group.id);
      } catch (e) {
        RuntimeLog.warn(TAG, `自动更新失败 ${group.name}: ${JSON.stringify(e)}`);
      }
    }
  }

  static async deleteGroup(groupId: string): Promise<void> {
    await Database.deleteGroup(groupId);
    RuntimeLog.info(TAG, `已删除订阅分组 ${groupId}`);
  }

  static async loadNodes(groupId: string): Promise<Node[]> {
    return Database.loadNodes(groupId);
  }
}
