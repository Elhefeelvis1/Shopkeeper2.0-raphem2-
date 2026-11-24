import logStockTransaction from './updateStockChanges.js'; // Ensure path is correct

export default async function savePurchase(userId, purchaseData, client, res) {
    const items = purchaseData?.items;
    const supplierId = purchaseData?.supplierId;

    // 1. Initial Validation BEFORE acquiring transaction locks
    if (!userId || !Array.isArray(items) || items.length === 0) {
        return res.status(400).json({ message: 'Invalid purchase data provided. Items array is required.' });
    }

    try {
        await client.query('BEGIN');

        // 2. Create Purchase Header
        const purchaseResult = await client.query(
            `INSERT INTO purchases (user_id, total_amount, supplier_id) VALUES ($1, $2, $3) RETURNING id;`,
            [userId, 0.00, supplierId]
        );
        const purchaseId = purchaseResult.rows[0].id;

        let totalPurchaseAmount = 0;

        // 3. Loop through items
        for (const item of items) {
            const { item_id: productId, item_name: itemName, quantity: rawQty, unit_cost: rawUnitCost, unit_price: rawUnitSellPrice, wholesale_price: rawWholesalePrice, expiry_date: expiryDate } = item;
            const quantity = parseFloat(rawQty) || 0;
            const unitCost = parseFloat(rawUnitCost) || 0;
            const unitSellPrice = parseFloat(rawUnitSellPrice) || 0;
            const wholesalePrice = parseFloat(rawWholesalePrice) || 0;
            const displayName = itemName || `Product ID: ${productId}`;

            // Strict Validation
            if (quantity <= 0 || unitCost <= 0 || !productId) {
                await client.query('ROLLBACK');
                return res.status(400).json({ message: `Invalid item data for ${displayName}` });
            }

            let lotExpiry = null;
            if (expiryDate && String(expiryDate).trim() !== '') {
                const eDate = new Date(expiryDate);
                if (isNaN(eDate.getTime())) {
                    await client.query('ROLLBACK');
                    return res.status(400).json({ message: `${displayName} has an invalid expiry date.` });
                }
                const currentDate = new Date();
                currentDate.setHours(0, 0, 0, 0);
                if (eDate < currentDate) {
                    await client.query('ROLLBACK');
                    return res.status(400).json({ message: `${displayName} has an expiry date in the past.` });
                }
                lotExpiry = expiryDate;
            }

            if (parseFloat(unitCost) > parseFloat(unitSellPrice)) {
                await client.query('ROLLBACK');
                return res.status(400).json({ message: `Unit cost cannot be greater than unit price for ${displayName}` });
            }

            const lineTotalCost = quantity * unitCost;
            totalPurchaseAmount += lineTotalCost;

            // A. Insert Line Item
            const purchaseLineResult = await client.query(
                `INSERT INTO purchase_line_items (purchase_id, product_id, quantity_purchased, cost_per_unit)
                 VALUES ($1, $2, $3, $4) RETURNING id;`,
                [purchaseId, productId, quantity, unitCost]
            );
            const purchaseLineItemId = purchaseLineResult.rows[0].id;

            // B. Create Stock Lot (This increases quantity via your database trigger)
            const lotResult = await client.query(
                `INSERT INTO stock_lots (product_id, quantity_in_lot, cost_per_unit, expiry_date)
                 VALUES ($1, $2, $3, $4) RETURNING lot_id;`,
                [productId, quantity, unitCost, lotExpiry]
            );
            const newLotId = lotResult.rows[0].lot_id;

            // C. Link Lot to Line Item
            await client.query('UPDATE purchase_line_items SET lot_id = $1 WHERE id = $2', [newLotId, purchaseLineItemId]);

            // D. Fetch quantity for Ledger (The snapshot)
            const stockCheck = await client.query(
                `SELECT total_quantity_in_stock FROM all_stocks WHERE id = $1`,
                [productId]
            );

            const newTotalStock = parseInt(stockCheck.rows[0].total_quantity_in_stock, 10);
            const oldTotalStock = newTotalStock - quantity;

            // E. Record Audit Log
            await logStockTransaction(client, {
                productId: productId,
                changeAmount: quantity,
                oldQty: oldTotalStock,
                newQty: newTotalStock,
                changeType: 'Purchase',
                costImpact: lineTotalCost,
                userId: userId,
                purchaseId: purchaseId,
                lotId: newLotId
            });

            // F. Update Product Metadata (Prices)
            if (rawWholesalePrice !== undefined && rawWholesalePrice !== null && rawWholesalePrice !== '') {
                await client.query(
                    `UPDATE all_stocks SET 
                        last_updated_date = NOW(),
                        last_cost_price = $1,
                        unit_selling_price = $2,
                        wholesale_price = $3
                    WHERE id = $4;`,
                    [unitCost, unitSellPrice, wholesalePrice, productId]
                );
            } else {
                await client.query(
                    `UPDATE all_stocks SET 
                        last_updated_date = NOW(),
                        last_cost_price = $1,
                        unit_selling_price = $2 
                    WHERE id = $3;`,
                    [unitCost, unitSellPrice, productId]
                );
            }
        }

        // 4. Update Header Total
        await client.query(
            `UPDATE purchases SET total_amount = $1 WHERE id = $2;`,
            [totalPurchaseAmount, purchaseId]
        );

        await client.query('COMMIT');
        return { success: true, purchaseId: purchaseId };

    } catch (error) {
        await client.query('ROLLBACK');
        console.error('Purchase Error:', error.message);
        throw error;
    }
}
