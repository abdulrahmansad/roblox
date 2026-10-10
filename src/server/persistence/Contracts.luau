-- Type boundary only. No DataStore schema or persistence backend is active yet.

export type StoredProfile<T> = {
    schemaVersion: number,
    data: T,
}

export type ProfileStore<T> = {
    load: (userId: number) -> (StoredProfile<T>?, string?),
    save: (userId: number, profile: StoredProfile<T>) -> (boolean, string?),
}

return table.freeze({})
