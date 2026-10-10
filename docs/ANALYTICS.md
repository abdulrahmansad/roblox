# Analytics foundation

No external analytics service is wired in this phase. Future gameplay should emit internal, server-owned domain events through a narrow analytics boundary so a provider can be added later without coupling gameplay to it. Avoid collecting personally identifying data; define event schemas and retention with the selected provider before integration.

Candidate events: first join, tutorial completion, first hatch, first mutation, first upgrade, first raid, successful steal, creature stolen from a player, session duration, return session, purchase funnel, purchase completion, and progression milestones. Record event context needed to measure cohorts and outcomes, not raw secrets or arbitrary client payloads. Client events can inform presentation but cannot prove rewards or purchases.
