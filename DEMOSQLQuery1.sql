USE PharmacyDB;
GO

-- (0) на всякий случай: убрать "висящие" транзакции
WHILE @@TRANCOUNT > 0 ROLLBACK;
GO

-- 19.1 Информация о лекарствах, которые продаются аптекой
-- (название, тип, количество, единица, цена, страна, поставщик, срок годности)
SELECT TOP(100)
    DrugID, DrugName, DrugType, Unit,
    Manufacturer, Country, SupplierName,
    MinRetailPrice, NearestExpiration
FROM dbo.vDrugCatalog
ORDER BY DrugName;
GO

-- 19.2 Подбор аналогов по составу (если нужного нет)
SELECT * FROM dbo.fn_SimilarDrugs(1, 5);
GO

-- 19.3 Остатки на складе
SELECT TOP(100)
    d.DrugID,
    d.Name AS DrugName,
    dbo.fn_StockQty(d.DrugID) AS StockQty
FROM dbo.Drug d
ORDER BY d.DrugID;
GO

-- 19.4 Список товаров, у которых остаток < 10
SELECT * FROM dbo.vReorderList ORDER BY StockQty;
GO

-- 19.4 Автоматическое формирование заказов
EXEC dbo.sp_CreateReorderOrders @MinQty = 10, @DefaultOrderQty = 25;
GO

SELECT TOP(10) * FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC;
SELECT TOP(50) * FROM dbo.PurchaseOrderItem ORDER BY PurchaseOrderItemID DESC;
GO

-- 19.5 Отслеживание выполнения заказов поставщиками (смена статуса)
DECLARE @po INT = (SELECT TOP(1) PurchaseOrderID FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC);
EXEC dbo.sp_SetPurchaseOrderStatus @PurchaseOrderID = @po, @NewStatus = N'Delivered';
SELECT * FROM dbo.PurchaseOrder WHERE PurchaseOrderID = @po;
GO

-- 19.6 Учет информации о поставщиках
SELECT * FROM dbo.Supplier ORDER BY SupplierID;
GO
