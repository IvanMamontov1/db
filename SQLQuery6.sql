CREATE OR ALTER VIEW dbo.v_CurrentStock
AS
SELECT
    d.DrugId,
    d.Name AS DrugName,
    ISNULL(SUM(b.Quantity), 0) AS TotalQty
FROM dbo.Drugs d
LEFT JOIN dbo.Batches b ON b.DrugId = d.DrugId
GROUP BY d.DrugId, d.Name;
GO
CREATE OR ALTER VIEW dbo.v_LowStockDrugs
AS
SELECT *
FROM dbo.v_CurrentStock
WHERE TotalQty < 10;
GO
CREATE OR ALTER VIEW dbo.v_DrugsEditable
AS
SELECT
    DrugId,
    Name,
    DrugType,
    Unit,
    RetailPrice,
    Country,
    Manufacturer,
    IsActive
FROM dbo.Drugs;
GO
SELECT * FROM dbo.v_CurrentStock;
SELECT * FROM dbo.v_LowStockDrugs;
-- Поставщик
INSERT INTO dbo.Suppliers(Name) VALUES (N'ТестПоставщик');

-- Лекарства
INSERT INTO dbo.Drugs(Name, DrugType, Unit, RetailPrice, Country, Manufacturer, IsActive)
VALUES
(N'Парацетамол 500', N'таблетки', N'уп', 120, N'Россия', N'Фармстандарт', 1),
(N'Аспирин 500',     N'таблетки', N'уп', 190, N'Германия', N'Bayer', 1);

-- Партии (остатки)
DECLARE @supId int = (SELECT TOP 1 SupplierId FROM dbo.Suppliers ORDER BY SupplierId DESC);

INSERT INTO dbo.Batches(DrugId, SupplierId, BatchNo, ExpiryDate, PurchasePrice, Quantity)
SELECT DrugId, @supId, N'B-001', DATEADD(month, 12, CAST(GETDATE() AS date)), 60, 6
FROM dbo.Drugs WHERE Name = N'Парацетамол 500';

INSERT INTO dbo.Batches(DrugId, SupplierId, BatchNo, ExpiryDate, PurchasePrice, Quantity)
SELECT DrugId, @supId, N'B-002', DATEADD(month, 12, CAST(GETDATE() AS date)), 100, 8
FROM dbo.Drugs WHERE Name = N'Аспирин 500';
