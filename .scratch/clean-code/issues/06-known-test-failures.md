# Fix or retire the two known failing tests
Status: done
Type: task

- App: `testCardRetryRetainsFullContextAndReturnsDetailedCards` (upstream Dayflow test).
- Briefing: `test_code_candidate_from_model_goes_through_gate`.
A clean gate needs both green. Find out whether the test or the code is wrong.

## Comments

- 2026-10-13 00:13: done (CHANGELOG 00:13). Briefing: a real gate bug (a site-packages `tests` package shadowed Briefing's); fixed with run_new_tests(). App: stale assertion updated to <previous_cards>.
