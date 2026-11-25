export const allowedTables = ['all_stocks', 'customers', 'suppliers', 'categories', 'units', 'wholesale_units', 'companies'];

export const importGenericCsv = async (req, res, db) => {
    try {
        const { tableName, mappings, data } = req.body;
        
        if (!allowedTables.includes(tableName)) {
            return res.status(403).json({ success: false, message: "Table not allowed for import" });
        }
        
        if (!data || data.length === 0) {
            return res.status(400).json({ success: false, message: "No data provided" });
        }

        // Get actual schema to validate mappings (on pool connection)
        const schemaResult = await db.query(`
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_name = $1 AND table_schema = 'public';
        `, [tableName]);
        const schemaCols = schemaResult.rows.map(r => r.column_name);
        const schemaTypes = {};
        schemaResult.rows.forEach(r => { schemaTypes[r.column_name] = r.data_type; });

        const targetCols = Object.keys(mappings).filter(col => schemaCols.includes(col));
        if (targetCols.length === 0) {
            return res.status(400).json({ success: false, message: "No valid mappings provided" });
        }

        // Acquire dedicated client for transaction
        const client = await db.connect();
        try {
            await client.query('BEGIN');
            
            let insertedCount = 0;
            for (const row of data) {
                const cols = [];
                const vals = [];
                const params = [];
                let pCounter = 1;

                for (const tCol of targetCols) {
                    const csvCol = mappings[tCol];
                    if (row[csvCol] !== undefined && row[csvCol] !== null && row[csvCol] !== "") {
                        let val = row[csvCol];
                        const dataType = schemaTypes[tCol];
                        if (dataType && ['numeric', 'integer', 'real', 'double precision', 'decimal', 'money'].includes(dataType) && typeof val === 'string') {
                            val = val.replace(/,/g, '');
                        }
                        cols.push(tCol);
                        params.push(val);
                        vals.push(`$${pCounter}`);
                        pCounter++;
                    }
                }

                if (cols.length > 0) {
                    const query = `INSERT INTO ${tableName} (${cols.join(', ')}) VALUES (${vals.join(', ')})`;
                    await client.query(query, params);
                    insertedCount++;
                }
            }
            
            await client.query('COMMIT');
            res.json({ success: true, message: `Successfully imported ${insertedCount} rows into ${tableName}` });
        } catch (err) {
            await client.query('ROLLBACK');
            throw err;
        } finally {
            client.release();
        }
    } catch (err) {
        console.error("Bulk import error:", err);
        res.status(500).json({ success: false, message: err.message });
    }
};

export const importStocksCsv = async (req, res, db) => {
    try {
        const { mappings, data } = req.body;
        
        if (!data || data.length === 0) {
            return res.status(400).json({ success: false, message: "No data provided" });
        }

        // 1. Upfront Validation Phase (on memory / pool, zero transaction holding time)
        const requiredCoreFields = ['name', 'unit', 'unit_selling_price'];
        for (const reqField of requiredCoreFields) {
            if (!mappings[reqField]) {
                return res.status(400).json({ success: false, message: `Validation Failed: Mapping for required field '${reqField}' is missing.` });
            }
        }

        for (let i = 0; i < data.length; i++) {
            const row = data[i];
            const itemName = mappings['name'] ? (row[mappings['name']] || `Row ${i + 1}`) : `Row ${i + 1}`;

            // Skip entirely blank rows (e.g. trailing empty CSV lines)
            const rowValues = Object.values(row).map(v => String(v ?? '').trim()).filter(v => v !== '');
            if (rowValues.length === 0) continue;

            for (const reqField of requiredCoreFields) {
                const mappedCsvHeader = mappings[reqField];
                const val = row[mappedCsvHeader];
                if (val === undefined || val === null || String(val).trim() === '') {
                    return res.status(400).json({ success: false, message: `Validation Failed: Row ${i + 1} ("${itemName}") has an empty required value for '${reqField}'.` });
                }
            }

            const priceCol = mappings['unit_selling_price'];
            const rawPrice = String(row[priceCol] ?? '').trim();
            let cleanPrice = rawPrice.replace(/[₦$€£]|NGN/gi, '').replace(/,/g, '').trim();
            if (cleanPrice === '-' || cleanPrice === '--' || cleanPrice === 'N/A' || cleanPrice === 'nil') {
                cleanPrice = '0';
            }
            const priceVal = parseFloat(cleanPrice);
            if (isNaN(priceVal) || priceVal < 0) {
                 return res.status(400).json({ 
                     success: false, 
                     message: `Validation Failed: Row ${i + 1} ("${itemName}") has an invalid selling price: "${rawPrice}".` 
                 });
            }

            const costCol = mappings['cost_per_unit'];
            if (costCol && row[costCol] !== undefined && row[costCol] !== "") {
                 const rawCost = String(row[costCol]).trim();
                 let cleanCost = rawCost.replace(/[₦$€£]|NGN/gi, '').replace(/,/g, '').trim();
                 if (cleanCost === '-' || cleanCost === '--' || cleanCost === 'N/A' || cleanCost === 'nil') {
                     cleanCost = '0';
                 }
                 const costVal = parseFloat(cleanCost);
                 if (isNaN(costVal) || costVal < 0) {
                     return res.status(400).json({ 
                         success: false, 
                         message: `Validation Failed: Row ${i + 1} ("${itemName}") has an invalid cost per unit: "${rawCost}".` 
                     });
                 }
            }

            const expiryCol = mappings['expiry_date'];
            if (expiryCol && row[expiryCol] && String(row[expiryCol]).trim() !== '') {
                const dateObj = new Date(row[expiryCol]);
                if (isNaN(dateObj.getTime())) {
                    return res.status(400).json({ success: false, message: `Validation Failed: Row ${i + 1} ("${itemName}") has an unparseable expiry date '${row[expiryCol]}'. Format must be YYYY-MM-DD.` });
                }
            }

            const reorderCol = mappings['reorder_level'];
            if (!reorderCol || row[reorderCol] === undefined || row[reorderCol] === "") {
                 return res.status(400).json({ success: false, message: `Validation Failed: Row ${i + 1} ("${itemName}") is missing the required reorder_level field.` });
            }
        }

        const userId = req.user ? req.user.id : (req.session?.passport?.user?.id || 1);

        const actualSchemaResult = await db.query(`
            SELECT column_name, data_type
            FROM information_schema.columns
            WHERE table_name = 'all_stocks' AND table_schema = 'public';
        `);
        const allStockValidCols = actualSchemaResult.rows.map(r => r.column_name);
        const allStockTypes = {};
        actualSchemaResult.rows.forEach(r => { allStockTypes[r.column_name] = r.data_type; });

        // 2. Database Transaction Phase (Acquire dedicated client)
        const client = await db.connect();
        try {
            await client.query('BEGIN');
            
            let insertedCount = 0;
            
            for (const row of data) {
                // Skip entirely blank rows
                const rowValues = Object.values(row).map(v => String(v ?? '').trim()).filter(v => v !== '');
                if (rowValues.length === 0) continue;

                // Resolve Unit ID
                let unitId = null;
                const unitCol = mappings['unit'];
                const unitName = row[unitCol];
                const unitRes = await client.query('SELECT id FROM units WHERE name = $1', [unitName]);
                if (unitRes.rows.length > 0) {
                    unitId = unitRes.rows[0].id;
                } else {
                    const newUnit = await client.query('INSERT INTO units (name) VALUES ($1) RETURNING id', [unitName]);
                    unitId = newUnit.rows[0].id;
                }

                // Resolve Category ID
                let categoryId = null;
                const catCol = mappings['category'];
                if (catCol && row[catCol]) {
                    const catName = row[catCol];
                    const catRes = await client.query('SELECT id FROM categories WHERE name = $1', [catName]);
                    if (catRes.rows.length > 0) {
                        categoryId = catRes.rows[0].id;
                    } else {
                        const newCat = await client.query('INSERT INTO categories (name) VALUES ($1) RETURNING id', [catName]);
                        categoryId = newCat.rows[0].id;
                    }
                } else {
                    categoryId = 0; // Uncategorized default
                }

                // Resolve Supplier ID (Optional)
                let supplierId = null;
                const supCol = mappings['supplier'];
                if (supCol && row[supCol]) {
                    const supName = row[supCol];
                    const supRes = await client.query('SELECT id FROM suppliers WHERE name = $1', [supName]);
                    if (supRes.rows.length > 0) {
                        supplierId = supRes.rows[0].id;
                    } else {
                        const newSup = await client.query('INSERT INTO suppliers (name) VALUES ($1) RETURNING id', [supName]);
                        supplierId = newSup.rows[0].id;
                    }
                }

                // Resolve Company ID (Optional)
                let companyId = null;
                const compCol = mappings['company'];
                if (compCol && row[compCol] !== undefined && row[compCol] !== null && String(row[compCol]).trim() !== '') {
                    const compVal = String(row[compCol]).trim();
                    const compNum = parseInt(compVal, 10);
                    if (!isNaN(compNum)) {
                        const compRes = await client.query('SELECT id FROM companies WHERE id = $1', [compNum]);
                        if (compRes.rows.length > 0) companyId = compRes.rows[0].id;
                    }
                    if (!companyId) {
                        const compRes = await client.query('SELECT id FROM companies WHERE name = $1', [compVal]);
                        if (compRes.rows.length > 0) {
                            companyId = compRes.rows[0].id;
                        } else if (isNaN(compNum)) {
                            const newComp = await client.query('INSERT INTO companies (name) VALUES ($1) RETURNING id', [compVal]);
                            companyId = newComp.rows[0].id;
                        }
                    }
                }

                // Build insert parameters for all_stocks
                // Explicitly include company_id as NULL or resolved ID to prevent PostgreSQL falling back to DEFAULT 0
                const cols = ['user_id', 'unit_id', 'category_id', 'company_id'];
                const vals = ['$1', '$2', '$3', '$4'];
                const params = [userId, unitId, categoryId, companyId];
                let pCounter = 5;

                if (supplierId) {
                    cols.push('supplier_id');
                    vals.push(`$${pCounter}`);
                    params.push(supplierId);
                    pCounter++;
                }

                const directFields = ['name', 'barcode', 'generic_name', 'reorder_level', 'unit_selling_price', 'wholesale_price'];
                
                for (const field of directFields) {
                    const csvCol = mappings[field];
                    if (csvCol && row[csvCol] !== undefined && row[csvCol] !== null && row[csvCol] !== "") {
                        if (allStockValidCols.includes(field)) {
                            let val = row[csvCol];
                            const dType = allStockTypes[field];
                            if (dType && ['numeric', 'integer', 'real', 'double precision', 'decimal', 'money'].includes(dType) && typeof val === 'string') {
                                val = val.replace(/[₦$€£]|NGN/gi, '').replace(/,/g, '').trim();
                                if (val === '-' || val === '--' || val === 'N/A' || val === 'nil') val = '0';
                            }
                            cols.push(field);
                            vals.push(`$${pCounter}`);
                            params.push(val);
                            pCounter++;
                        }
                    }
                }

                const query = `
                    INSERT INTO all_stocks (${cols.join(', ')})
                    VALUES (${vals.join(', ')})
                    RETURNING id;
                `;
                const result = await client.query(query, params);
                const productId = result.rows[0].id;
                
                // Handle stock_lots if quantity > 0
                const qtyCol = mappings['quantity'];
                const qtyStr = qtyCol && row[qtyCol] ? String(row[qtyCol]).replace(/,/g, '') : '0';
                const quantity = parseFloat(qtyStr);
                if (quantity > 0) {
                    const costCol = mappings['cost_per_unit'];
                    let costVal = row[costCol];
                    if (typeof costVal === 'string') {
                        costVal = costVal.replace(/[₦$€£]|NGN/gi, '').replace(/,/g, '').trim();
                        if (costVal === '-' || costVal === '--' || costVal === 'N/A' || costVal === 'nil') costVal = '0';
                    }
                    const expiryCol = mappings['expiry_date'];
                    
                    const expiryDateVal = (expiryCol && row[expiryCol] && String(row[expiryCol]).trim() !== '') ? row[expiryCol] : null;

                    await client.query(`
                        INSERT INTO stock_lots (product_id, quantity_in_lot, cost_per_unit, expiry_date)
                        VALUES ($1, $2, $3, $4)
                    `, [productId, quantity, costVal, expiryDateVal]);
                }
                
                insertedCount++;
            }
            
            await client.query('COMMIT');
            res.json({ success: true, message: `Successfully imported ${insertedCount} stock items.` });
        } catch (err) {
            await client.query('ROLLBACK');
            throw err;
        } finally {
            client.release();
        }
    } catch (err) {
        console.error("Bulk stock import error:", err);
        res.status(500).json({ success: false, message: err.message });
    }
};
