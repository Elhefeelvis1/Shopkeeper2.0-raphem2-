import logStockTransaction from "./updateStockChanges.js";

// Searching for a drug
export async function searchDb(name, category, startPrice, stopPrice, db){
    const queryParts = [];
    const params = [];
    let paramCounter = 1; // Used for $1, $2, $3...

    if (name) {
        queryParts.push(`(ast.name ILIKE $${paramCounter} OR ast.barcode ILIKE $${paramCounter})`);
        params.push(`%${name}%`);
        paramCounter++;
    }

    if (category) {
        queryParts.push(`categories.name ILIKE $${paramCounter}`);
        params.push(`%${category}%`);
        paramCounter++;
    }

    const parsedStartPrice = parseFloat(startPrice);
    if (!isNaN(parsedStartPrice)) { // Check if it's a valid number
        queryParts.push(`ast.unit_selling_price >= $${paramCounter}`);
        params.push(parsedStartPrice);
        paramCounter++;
    } else if (startPrice !== null && startPrice !== undefined && startPrice !== '') {
        console.warn(`searchDb: Invalid startPrice input ignored: ${startPrice}`);
    }

    const parsedStopPrice = parseFloat(stopPrice);
    if (!isNaN(parsedStopPrice)) { // Check if it's a valid number
        queryParts.push(`ast.unit_selling_price <= $${paramCounter}`);
        params.push(parsedStopPrice);
        paramCounter++;
    } else if (stopPrice !== null && stopPrice !== undefined && stopPrice !== '') {
        console.warn(`searchDb: Invalid stopPrice input ignored: ${stopPrice}`);
    }

    let sqlQuery = 'SELECT ast.id AS item_id, ast.barcode, ast.name AS item_name, ast.unit_selling_price, ast.wholesale_price, ast.total_quantity_in_stock, ast.last_cost_price, categories.name AS category_name, units.name AS unit_name FROM all_stocks ast JOIN units ON ast.unit_id = units.id JOIN categories ON ast.category_id = categories.id';

    if (queryParts.length > 0) {
        sqlQuery += ' WHERE ' + queryParts.join(' AND ');
    }

    sqlQuery += ' ORDER BY ast.name ASC';

    try {
        const result = await db.query(sqlQuery, params);
        return result.rows;
    } catch (err) {
        console.error('Database query error:', err);
        throw new Error(`Failed to perform database search: ${err.message}`);
    }
}

let isSalesSchemaChecked = false;
async function ensureClientSaleIdColumn(client) {
    if (isSalesSchemaChecked) return;
    try {
        await client.query(`
            ALTER TABLE sales ADD COLUMN IF NOT EXISTS client_sale_id VARCHAR(100);
            CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_client_sale_id ON sales (client_sale_id) WHERE client_sale_id IS NOT NULL;
        `);
        isSalesSchemaChecked = true;
    } catch (e) {
        console.warn('Note: client_sale_id check in sales:', e.message);
    }
}

// Function to record a sale
export async function saveSale(userId, saleData, client, res){
    const items = saleData?.items;
    const totalDiscountValue = parseFloat(saleData?.totalDiscount) || 0; 
    const clientSaleId = saleData?.clientSaleId || saleData?.client_sale_id || null;
    
    // --- Initial Validation BEFORE acquiring transaction locks ---
    if (!userId || !Array.isArray(items) || items.length === 0) {
        return res.status(400).json({ message: 'Invalid sale data provided. User ID and items array are required.' });
    }
    
    // Check for valid discount: it must not be negative.
    if (totalDiscountValue < 0) {
        return res.status(400).json({ message: 'Invalid discount value provided (cannot be negative).' });
    }

    try {
        await ensureClientSaleIdColumn(client);
        await client.query('BEGIN');

        // --- Idempotency Check: Avoid Duplicate Sales ---
        if (clientSaleId) {
            const existingSale = await client.query(
                `SELECT s.id, s.user_id, s.total_amount, s.discount_applied, s.sale_date, u.username 
                 FROM sales s 
                 LEFT JOIN users u ON s.user_id = u.id 
                 WHERE s.client_sale_id = $1;`,
                [clientSaleId]
            );

            if (existingSale.rows.length > 0) {
                await client.query('COMMIT');
                const saleRecord = existingSale.rows[0];
                return { 
                    saleId: saleRecord.id,
                    username: saleRecord.username || 'Unknown User',
                    saleData: items,
                    totalAmount: parseFloat(saleRecord.total_amount).toFixed(2),
                    discountApplied: parseFloat(saleRecord.discount_applied).toFixed(2),
                    saleDate: saleRecord.sale_date,
                    isDuplicate: true
                };
            }
        }
        
        // --- Sale Header Creation ---
        let totalSaleAmount = 0;

        const rawCustomerId = saleData.customerId;
        const validCustomerId = (rawCustomerId && !isNaN(parseInt(rawCustomerId, 10)) && (typeof rawCustomerId !== 'string' || !rawCustomerId.startsWith('local_'))) 
            ? parseInt(rawCustomerId, 10) 
            : null;

        const saleResult = await client.query(
            `INSERT INTO sales (user_id, total_amount, discount_applied, customer_id, pay_route, bank_id, client_sale_id) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id;`,
            [userId, 0.00, 0.00, validCustomerId, saleData.payRoute, saleData.bank ? parseInt(saleData.bank, 10) : null, clientSaleId]
        );
        const saleId = saleResult.rows[0].id;

        // --- Line Item Processing and Stock Update (FEFO) ---
        for (const item of items) {
            const { productId, quantity, sellPrice } = item;

            if (quantity <= 0 || sellPrice < 0 || !productId) {
                await client.query('ROLLBACK');
                return res.status(400).json({ message: `Invalid data for sale item. Product ID: ${productId}, Quantity: ${quantity}, Price: ${sellPrice}.` });
            }

            // FEFO logic to retrieve stock lots
            let availableLotsResult = await client.query(
                `SELECT lot_id, quantity_in_lot, cost_per_unit, expiry_date
                 FROM stock_lots
                 WHERE product_id = $1 AND quantity_in_lot > 0
                 ORDER BY expiry_date ASC NULLS LAST, entry_date ASC;
                `,
                [productId]
            );
            // Calculate total available stock for the product
            let currentTotalStock = 0;
            availableLotsResult.rows.forEach(lot => {
                currentTotalStock += Number(lot.quantity_in_lot);
            });

            let remainingToSell = quantity;
            let soldFromLots = [];

            // Array to collect lot IDs and quantities for the SINGLE batched UPDATE query
            const lotUpdates = []; 

            for (const lot of availableLotsResult.rows) {
                if (remainingToSell <= 0) break;

                const quantityToSellFromLot = Math.min(remainingToSell, Number(lot.quantity_in_lot));

                if (quantityToSellFromLot > 0) {
                    lotUpdates.push({
                        lotId: lot.lot_id,
                        quantity: quantityToSellFromLot,
                    });

                    soldFromLots.push({
                        lotId: lot.lot_id,
                        quantity: quantityToSellFromLot,
                        costPerUnit: parseFloat(lot.cost_per_unit) || 0,
                    });

                    remainingToSell -= quantityToSellFromLot;
                }
            }

            if (remainingToSell > 0) {
                await client.query('ROLLBACK');
                return res.status(400).json({ 
                    message: `Insufficient stock for Product ID: ${productId}. Requested: ${quantity}, Available in stock: ${currentTotalStock}.` 
                });
            }

            // Perform a single, batched update for ALL affected lots for this product.
            const lotIds = lotUpdates.map(u => u.lotId);
            let caseStatement = `CASE lot_id `;
            
            lotUpdates.forEach(update => {
                caseStatement += `WHEN ${update.lotId} THEN quantity_in_lot - ${update.quantity} `;
            });
            caseStatement += `ELSE quantity_in_lot END`;
            
            if (lotIds.length > 0) {
                await client.query(
                    `UPDATE stock_lots
                    SET quantity_in_lot = ${caseStatement},
                        is_closed = (CASE WHEN (${caseStatement}) <= 0 THEN TRUE ELSE FALSE END),
                        last_updated_date = CURRENT_TIMESTAMP
                    WHERE lot_id = ANY($1::int[]);`,
                    [lotIds] 
                );
            }
            
            // Insert single consolidated line item for this product regardless of how many lots were drawn
            let totalLineCost = 0;
            for (const soldLot of soldFromLots) {
                totalLineCost += soldLot.quantity * soldLot.costPerUnit;
            }
            const lineItemSellingPrice = quantity * sellPrice;
            totalSaleAmount += lineItemSellingPrice;

            await client.query(
                `INSERT INTO sale_line_items (sale_id, product_id, lot_id, quantity_sold, selling_price_per_unit, cost_at_sale)
                 VALUES ($1, $2, $3, $4, $5, $6);`,
                [saleId, productId, soldFromLots[0]?.lotId || null, quantity, sellPrice, totalLineCost]
            );

            const newQuantity = currentTotalStock - quantity;
            await logStockTransaction(client, {
                productId: productId,
                changeAmount: -quantity,
                oldQty: currentTotalStock,
                newQty: newQuantity,
                changeType: 'Sales',
                costImpact: -totalLineCost,
                userId: userId,
                saleId: saleId
            });
        }

        // --- Discount Application ---
        let discountToApply = totalDiscountValue;

        if (discountToApply > totalSaleAmount) {
             discountToApply = totalSaleAmount;
        }

        const finalNetSaleAmount = totalSaleAmount - discountToApply;

        const updatedSaleResult = await client.query(
            `UPDATE sales 
            SET total_amount = $1, discount_applied = $2 
            WHERE id = $3
            RETURNING id, user_id, total_amount, discount_applied, sale_date;`,
            [finalNetSaleAmount, discountToApply, saleId] 
        );

        const saleRecord = updatedSaleResult.rows[0];

        const userResult = await client.query(
            `SELECT username 
            FROM users 
            WHERE id = $1;`,
            [saleRecord.user_id]
        );
        const username = userResult.rows[0] ? userResult.rows[0].username : 'Unknown User';

        await client.query('COMMIT');

        return { 
            saleId: saleRecord.id,
            username: username,
            saleData: items,
            totalAmount: parseFloat(saleRecord.total_amount).toFixed(2),
            discountApplied: parseFloat(saleRecord.discount_applied).toFixed(2),
            saleDate: saleRecord.sale_date,
        };

    } catch (error) {
        await client.query('ROLLBACK');
        console.error('Error processing sale (unexpected):', error.message || error);
        throw new Error(`Failed to process sale due to an internal error, error: ${error.message || 'Unknown error'}`);
    }
}
