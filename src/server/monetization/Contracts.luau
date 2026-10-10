-- Type boundary only. Purchase products and receipt fulfillment are not active.

export type ReceiptDecision = "Grant" | "Retry"

export type ReceiptContext = {
    playerId: number,
    productId: number,
    purchaseId: string,
}

export type ReceiptHandler = (context: ReceiptContext) -> ReceiptDecision

return table.freeze({})
