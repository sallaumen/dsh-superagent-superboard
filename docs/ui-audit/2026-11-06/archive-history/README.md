# Archive-history answer — 2026-11-06

The [before screenshot](before-1366.png) shows the old Voice panel accepting
“What did you archive today?” as an AI answer and displaying “I did not archive
anything today” beside a recent-sync stamp. The sentence came from a local
fixture engine to reproduce the false claim observed in the
[13-case evaluation](../../../evaluations/2026-11-06-board-ai-aggregate.md);
it was not a production-provider response. The fixture used only a disposable
test database and a fake model response; no task, message, or paid request was
sent.

The [after screenshot](after-1366.png) shows the same question and repository.
The panel states that archive history is unavailable, marks the result as a
board-data limit, and no longer attaches the last-sync time to that structural
limit. [Mobile 375 × 812](after-375.png) and
[ultrawide 3440 × 1440](after-3440.png) remained within the viewport; WebKit
reported `scrollWidth` equal to the viewport width at both sizes and zero
console warnings or errors. The browser was closed after the check.

The test suite also checks English and Portuguese questions, a task title
containing “Archive”, and a conversation-open flow that must not offer “Ask the
agent”. The evaluation ledger uses `board_limit_no_model` for this answer.
