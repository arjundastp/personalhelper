# Claude routine for the DayMate Team summary

Run this as a **scheduled routine** in your company's Claude, with the **Microsoft 365 connector** enabled
(the same way your colleague's routine reads Teams).

## Before you paste the prompt

1. **Schedule:** every weekday at about **6:45 AM IST** (DayMate checks when you open it).
2. **Connector:** enable **Microsoft 365** for this routine (only this one is needed).
3. **Network:** the routine's environment must be allowed to reach your Worker host
   `daymate-summary.<your-subdomain>.workers.dev` (add it to the environment's allowed hosts).
4. **Keep the write key out of the prompt.** Store it in the routine's environment instead:
   - environment variable `DAYMATE_ENDPOINT` = `https://daymate-summary.<your-subdomain>.workers.dev`
   - secret `DAYMATE_WRITE_KEY` = your **WRITE_KEY**, or a *network secret* for the Worker host that adds the header
     `Authorization: Bearer <WRITE_KEY>`; then drop the `-H "Authorization: …"` part of the command below.

   If your Claude has no place for secrets, you can put the values directly into the command in the prompt, but then
   anyone who can see the routine can see the key.

## The prompt (copy everything in the box)

```text
You are my daily Microsoft Teams summariser. Every run, summarise YESTERDAY's Teams activity for me and send it to my DayMate endpoint.

STRICT RULES
- Use the Microsoft 365 connector ONLY to read. Never send, post, reply, react, edit, delete, forward, schedule or create anything in Teams, Outlook or anywhere in Microsoft 365. If a step would need a write action, skip it.
- Send the summary ONLY to my DayMate endpoint (step 4). Do not send it, or any message content, anywhere else.
- Do not copy passwords, keys, tokens, bank or personal ID numbers, or health details into the summary. Summarise around them.
- My time zone is IST (India Standard Time, Asia/Kolkata, UTC+05:30). "Yesterday" means 00:00–23:59 IST of the previous day.

WHAT MATTERS TO ME (put these first, skip small talk)
1. PULSE: anything about Pulse – messages, chats or channels that mention Pulse, and discussions about its work, releases, issues, decisions, deadlines, metrics or people working on it. Treat a chat or channel with "Pulse" in its name as Pulse-related.
2. NEEDS MY ATTENTION: I am @mentioned or named; someone asks me a question, asks for my review, approval, input or decision; a task is assigned to me; a deadline, escalation, blocker, incident or customer issue involves me or my work; my manager or lead says something to me directly; a question to me is still unanswered.
3. Everything else: only important decisions or changes. Leave out greetings, thanks, jokes, emoji-only replies and routine chatter.

STEPS
1. Work out yesterday's date (YYYY-MM-DD) in my time zone.

2. Using the Microsoft 365 connector, read my Teams messages from yesterday:
   - my 1:1 chats, group chats and meeting chats;
   - channel messages in teams/channels I am a member of, if the connector allows it.
   Skip system messages (joins, renames, call started/ended). If there is a lot, cover the 30 most active chats/channels and anything where I am @mentioned or asked something directly.

3. Write the summary as JSON in EXACTLY this shape (no extra text around it), and save it to a file summary.json:
{
  "date": "YYYY-MM-DD",
  "generatedAt": <current time as Unix epoch milliseconds>,
  "account": "Claude routine",
  "highlights": ["3 to 6 short sentences. Pulse items first, each starting with 'Pulse: '. Then items that need my attention, then any other important decision"],
  "actions": [
    {"text": "What I need to do or answer, who asked, and by when if known. Start with 'Pulse: ' if it is about Pulse", "source": "chat or channel name"}
  ],
  "chats": [
    {"name": "chat/channel name, or 'Chat with <person>' for 1:1", "count": <number of messages that day>,
     "points": ["up to 3 short bullet points of what was discussed or decided"]}
  ],
  "diagnostics": {"model": "Claude routine", "mode": "Claude routine", "messages": <total messages read>, "chatsWithMessages": <number of chats in 'chats'>}
}
   Rules for the JSON:
   - Plain, short English. Each highlight and point under 160 characters.
   - "actions": everything from "NEEDS MY ATTENTION" above, most urgent first (Pulse items before others at the same urgency). Do not miss an unanswered question to me. Use [] if none.
   - "chats": Pulse-related chats/channels first, then chats with something for me, then the rest by activity. Leave out chats that had only small talk.
   - If there was nothing about Pulse, do not invent anything; just leave Pulse out.
   - If there were no messages at all, still send the JSON with "highlights": ["No Teams messages yesterday."] and empty lists.

4. Send it with this exact command (and nothing else that sends data):
   curl -sS -X POST "$DAYMATE_ENDPOINT/summaries" -H "Authorization: Bearer $DAYMATE_WRITE_KEY" -H "Content-Type: application/json" --data @summary.json
   The answer should be {"ok":true,"date":"YYYY-MM-DD"}. If not, retry once after 30 seconds. If it still fails, stop and report the error.

5. Finish with ONE line only, without the summary content:
   "Sent DayMate summary for <date>: <N> chats, <M> messages."
```

## Test it once

Run the routine manually once, then in DayMate tap **Team summary → Check now**. You should see yesterday's
summary with Highlights, Might need your action, and By chat.
