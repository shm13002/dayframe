// What an approval card shows and offers. Ported from Herald OS lib/approval-choices.ts
// (MIT, Luke The Dev): system tools ask through Hermes's own approval request, labelled
// "<tool> (plugin approval rule)", and destructive actions never offer "session" or "always".
import type { ApprovalChoice } from "./hermes/upstream/gateway-events";

const PLUGIN_RULE_RE = /^<([a-z0-9_]+)> \(plugin approval rule\)$/i;
const BRIDGE_DESTRUCTIVE = new Set(["system_kill_process"]);
const DESTRUCTIVE_SUMMARY_RE = /^(trash|force quit|force kill|terminate|quit)\b/i;
const KNOWN: readonly ApprovalChoice[] = ["once", "session", "always", "deny"];

export interface ApprovalShape {
  command?: string | null;
  description?: string | null;
  tool_name?: string | null;
  choices?: readonly string[] | null;
  allow_permanent?: boolean | null;
  allow_session?: boolean | null;
}

export interface ApprovalFacts {
  toolName: string | null;
  destructive: boolean;
  choices: ApprovalChoice[];
}

export function approvalFacts(params: ApprovalShape): ApprovalFacts {
  const bridgeTool = PLUGIN_RULE_RE.exec(params.command ?? "")?.[1] ?? null;
  const destructive =
    bridgeTool !== null &&
    (BRIDGE_DESTRUCTIVE.has(bridgeTool) || DESTRUCTIVE_SUMMARY_RE.test(params.description ?? ""));
  const asked = (params.choices?.length ? params.choices : ["once", "deny"]).filter(
    (choice): choice is ApprovalChoice => KNOWN.includes(choice as ApprovalChoice),
  );
  const choices = asked.filter((choice) => {
    if (choice === "always") return params.allow_permanent !== false && !destructive;
    if (choice === "session") return params.allow_session !== false && !destructive;
    return true;
  });
  return { toolName: params.tool_name ?? bridgeTool, destructive, choices };
}

export const CHOICE_LABEL: Record<ApprovalChoice, string> = {
  once: "Allow once",
  session: "Allow this session",
  always: "Always allow",
  deny: "Deny",
};

/** Plain names for the system tools in tool rows. */
const TOOL_LABEL: Record<string, string> = {
  system_info: "Checked the Mac",
  system_processes: "Looked at running programs",
  system_disk_usage: "Measured disk space",
  system_find_files: "Searched files",
  system_apps: "Looked at apps",
  system_network: "Checked the network",
  system_logs: "Read logs",
  system_control: "Changed a Mac setting",
  system_open: "Opened something",
  system_kill_process: "Stopped a program",
  system_files: "Worked with files",
  system_documents: "Read documents",
  mcp__dayflow__get_timeline: "Read your timeline",
  mcp__dayflow__get_daily: "Read your day",
  mcp__dayflow__search_activities: "Searched your timeline",
  mcp__dayflow__get_time_breakdown: "Added up your time",
  mcp__dayflow__get_status: "Checked the timeline",
  mcp__dayflow__get_weekly: "Read your week",
  mcp__dayflow__get_activity_detail: "Read an activity",
  mcp__dayflow__list_categories: "Read your categories",
  skill_view: "Read its playbook",
  terminal: "Ran a command",
  web_search: "Searched the web",
  memory: "Used memory",
};

export function toolLabel(name: string): string {
  return TOOL_LABEL[name] ?? name.replace(/^mcp__[a-z0-9-]+__/, "").replace(/_/g, " ");
}
