// PURE prompt-assembly for the chat function — no I/O, no env, fully unit-testable without a
// key (assemble_test.ts). The C3 folded quarantine LIVES HERE as a code path (M4-CONTRACTS §4):
// folded events render ONLY into the fenced SEALED MEMORIES block; the open record never
// contains them. The prompt-suite's live folded-no-reraise-chat case tests the model side;
// this module's test proves the assembly side deterministically.

export interface WirePerson {
  id: string;
  name: string;
  relation: string;
  mood: string;
  roleFlags: string[];
  rituals: string[];
  notes: string;
  priority: number;
}

export interface WireEvent {
  id: string;
  title: string;
  body: string;
  date: string;
  valence: string;
  isOpen: boolean;
  isHealed: boolean;
  healedReason?: string | null;
  isUpcoming: boolean;
}

export interface WireCommitment {
  id: string;
  personId?: string | null;
  text: string;
  dateMade: string;
  status: string;
}

export interface WireGoal {
  id: string;
  text: string;
  targetDate?: string | null;
  progressNote: string;
}

export interface WireCrossLink {
  otherChapterTitle: string;
  note: string;
}

export interface WireChatContext {
  userName: string;
  chapter: {
    id: string;
    type: string;
    title: string;
    state: string;
    awarenessPct: number;
    filledSlots: string[];
  };
  people: WirePerson[];
  events: WireEvent[];
  commitments: WireCommitment[];
  goals: WireGoal[];
  crossLinks: WireCrossLink[];
}

export interface WireTurn {
  author: "pom" | "user";
  text: string;
}

export const SEALED_MEMORIES_HEADER = "SEALED MEMORIES (healed & folded — do not raise unprompted):";

const SEALED_MEMORIES_RULE =
  "These were worked through and folded by the user. NEVER mention them unless the user brings " +
  "one up first. If they do, respond gently — forgiveness was their choice and their strength — " +
  "and never use these as ammunition, evidence, or part of a pattern.";

/** Renders the chapter record. Folded events appear ONLY under the sealed header. */
export function assembleContextBlock(context: WireChatContext): string {
  const open = context.events.filter((event) => !event.isHealed);
  const sealed = context.events.filter((event) => event.isHealed);

  const lines: string[] = [];
  lines.push(`USER: ${context.userName || "(unnamed)"}`);
  lines.push(
    `THE CHAPTER: "${context.chapter.title}" · type ${context.chapter.type} · state ` +
      `${context.chapter.state} · awareness ${context.chapter.awarenessPct}%`,
  );

  lines.push("PEOPLE:");
  if (context.people.length === 0) lines.push("  (none on record)");
  for (const person of context.people) {
    const flags = person.roleFlags.length ? ` · roles: ${person.roleFlags.join(", ")}` : "";
    const rituals = person.rituals.length ? ` · rituals: ${person.rituals.join("; ")}` : "";
    const notes = person.notes ? ` · notes: ${person.notes}` : "";
    lines.push(`  [${person.id}] ${person.name} (${person.relation}) · mood ${person.mood}${flags}${rituals}${notes}`);
  }

  lines.push("TIMELINE (the open record):");
  if (open.length === 0) lines.push("  (nothing kept yet)");
  for (const event of open) {
    const tags = [
      event.valence,
      event.isOpen ? "OPEN" : null,
      event.isUpcoming ? "UPCOMING" : null,
    ].filter(Boolean).join(" · ");
    lines.push(`  [${event.id}] ${event.date} — ${event.title} (${tags}): ${event.body}`);
  }

  lines.push("RECEIPTS (promises on record):");
  if (context.commitments.length === 0) lines.push("  (none on record)");
  for (const commitment of context.commitments) {
    lines.push(`  [${commitment.id}] ${commitment.dateMade} — "${commitment.text}" · status ${commitment.status}`);
  }

  if (context.goals.length > 0) {
    lines.push("GOALS:");
    for (const goal of context.goals) {
      const target = goal.targetDate ? ` · by ${goal.targetDate}` : "";
      const progress = goal.progressNote ? ` · ${goal.progressNote}` : "";
      lines.push(`  [${goal.id}] ${goal.text}${target}${progress}`);
    }
  }

  if (context.crossLinks.length > 0) {
    lines.push("CROSS-LINKS (threads into other chapters):");
    for (const link of context.crossLinks) {
      lines.push(`  ↔ "${link.otherChapterTitle}": ${link.note}`);
    }
  }

  if (sealed.length > 0) {
    lines.push(SEALED_MEMORIES_HEADER);
    lines.push(SEALED_MEMORIES_RULE);
    for (const event of sealed) {
      const reason = event.healedReason ? ` (their words: "${event.healedReason}")` : "";
      lines.push(`  [${event.id}] ${event.date} — ${event.title}${reason}`);
    }
  }

  return lines.join("\n");
}

/** The single user message: context + recent transcript + the new turn (layers 4–5, never cached). */
export function assembleUserMessage(
  context: WireChatContext,
  history: WireTurn[],
  userText: string | null,
  clientTime: string,
  locale: string,
): string {
  const transcript = history.length === 0 ? "(this is the first turn in this room)" : history
    .map((turn) => `${turn.author === "user" ? context.userName || "user" : "Pom"}: ${turn.text}`)
    .join("\n");
  const turn = userText === null
    ? "(the user tapped continue — move the prep flow forward)"
    : userText;
  return `clientTime: ${clientTime}
locale: ${locale}

${assembleContextBlock(context)}

RECENT CONVERSATION:
${transcript}

THE USER SAYS:
${turn}`;
}
