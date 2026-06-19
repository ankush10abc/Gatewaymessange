Before implementing any change:

1. Analyze the complete feature flow end-to-end.
2. Understand existing architecture, state management, repository pattern, caching strategy, API flow, and navigation flow.
3. Identify root cause instead of patching symptoms.
4. Reuse existing services, repositories, models, providers, utilities, extensions, and widgets whenever possible.
5. Avoid duplicate code, duplicate API calls, duplicate state, and duplicate business logic.
6. Prefer extending existing functions over creating new ones.
7. Keep implementation production-ready, scalable, and maintainable.
8. Minimize code size while maximizing functionality.
9. Use single-responsibility methods.
10. Extract reusable logic into shared methods only when reused multiple times.
11. Avoid unnecessary files, classes, wrappers, abstractions, and documentation.
12. Preserve existing functionality and backward compatibility.
13. Check for memory leaks, stream leaks, listener leaks, and unnecessary rebuilds.
14. Optimize API requests, database operations, and widget rebuilds.
15. Follow existing project architecture and naming conventions.
16. Before writing code, create an internal implementation plan and verify dependencies.
17. After implementation, verify all affected flows still work correctly.
18. Prefer low-code, reusable, and performance-optimized solutions.
19. Do not create documentation, markdown files, summary files, or implementation report files.
20. Implement only the required change with the smallest clean solution that solves the complete problem.
21. Chat opens in <100ms, no loaders, works offline, syncs in background!
22. don't forget to add a comment to the code
23. Do not create documentation or md or text or dart files for implemented summery.
20. Implement only the required change with the smallest clean solution that solves the complete problem.
21. LOW CODE, HIGH REUSABILITY
- Prefer reusable widgets, services, extensions, utilities, and helpers.
- Avoid duplicate code.
- Extract common logic into reusable functions.
- Follow DRY principles.
UNDERSTAND FIRST
- Read all related files before making changes.
- Trace the complete flow from UI → ViewModel/Controller → Repository → API/Database.
- Understand existing architecture, state management, navigation, models, and dependencies.
- Do not assume behavior.
- Identify root cause before coding.
PLAN BEFORE IMPLEMENTATION
- Create a short implementation plan.
- List affected files.
- List risks and edge cases.
- Verify plan against existing architecture.
- Reuse existing code whenever possible.
ROOT CAUSE FIXES ONLY
- Never apply temporary fixes.
- Fix the actual source of the issue.
- Check downstream and upstream dependencies.
- Ensure no regression is introduced.

