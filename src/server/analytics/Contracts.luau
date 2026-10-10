-- Internal event boundary only. No external analytics provider is wired in.

export type EventProperties = { [string]: string | number | boolean }

export type DomainEvent = {
    name: string,
    playerUserId: number?,
    occurredAt: number,
    properties: EventProperties?,
}

export type AnalyticsSink = {
    record: (event: DomainEvent) -> (),
}

return table.freeze({})
