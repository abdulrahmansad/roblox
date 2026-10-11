-- Shared shape for the private, server-owned playtest event boundary.

export type EventProperties = { [string]: string | number | boolean }

export type DomainEvent = {
    event: string,
    sessionId: string,
    elapsedSeconds: number,
    properties: EventProperties?,
}

export type AnalyticsSink = {
    record: (event: DomainEvent) -> (),
}

return table.freeze({})
