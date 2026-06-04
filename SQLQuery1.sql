/*==============================================================
  PharmacyDB (Вариант 19): Информационная поддержка аптеки
  Таблицы >= 10, 3 VIEW, 3 FUNCTION, 3 PROC, 3 TRIGGER, 3НФ
==============================================================*/

------------------------------------------------------------
-- 0. Пересоздание БД
------------------------------------------------------------
USE master;
GO
IF DB_ID(N'PharmacyDB') IS NOT NULL
BEGIN
    ALTER DATABASE PharmacyDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PharmacyDB;
END
GO

CREATE DATABASE PharmacyDB;
GO
USE PharmacyDB;
GO

------------------------------------------------------------
-- 1. Т А Б Л И Ц Ы  (12 шт.)
------------------------------------------------------------

-- 1.1 Страна-производитель
CREATE TABLE dbo.Country(
    CountryID INT IDENTITY(1,1) CONSTRAINT PK_Country PRIMARY KEY,
    Name NVARCHAR(120) NOT NULL CONSTRAINT UQ_Country_Name UNIQUE
);
GO

-- 1.2 Производитель
CREATE TABLE dbo.Manufacturer(
    ManufacturerID INT IDENTITY(1,1) CONSTRAINT PK_Manufacturer PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    CountryID INT NOT NULL,

    CONSTRAINT FK_Manufacturer_Country
        FOREIGN KEY (CountryID) REFERENCES dbo.Country(CountryID)
);
GO

-- 1.3 Поставщик
CREATE TABLE dbo.Supplier(
    SupplierID INT IDENTITY(1,1) CONSTRAINT PK_Supplier PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    INN NVARCHAR(20) NULL,
    Phone NVARCHAR(50) NULL,
    Email NVARCHAR(255) NULL,
    Address NVARCHAR(255) NULL
);
GO

-- 1.4 Единицы измерения
CREATE TABLE dbo.Unit(
    UnitID INT IDENTITY(1,1) CONSTRAINT PK_Unit PRIMARY KEY,
    Name NVARCHAR(80) NOT NULL,
    ShortName NVARCHAR(20) NOT NULL CONSTRAINT UQ_Unit_Short UNIQUE
);
GO

-- 1.5 Тип лекарственного средства
CREATE TABLE dbo.DrugType(
    DrugTypeID INT IDENTITY(1,1) CONSTRAINT PK_DrugType PRIMARY KEY,
    Name NVARCHAR(120) NOT NULL CONSTRAINT UQ_DrugType_Name UNIQUE
);
GO

-- 1.6 Действующее вещество
CREATE TABLE dbo.ActiveIngredient(
    IngredientID INT IDENTITY(1,1) CONSTRAINT PK_ActiveIngredient PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL CONSTRAINT UQ_Ingredient_Name UNIQUE
);
GO

-- 1.7 Лекарственное средство (карточка)
CREATE TABLE dbo.Drug(
    DrugID INT IDENTITY(1,1) CONSTRAINT PK_Drug PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    DrugTypeID INT NOT NULL,
    ManufacturerID INT NOT NULL,
    UnitID INT NOT NULL, -- упаковка/шт/флакон и т.д.

    CONSTRAINT FK_Drug_DrugType FOREIGN KEY (DrugTypeID) REFERENCES dbo.DrugType(DrugTypeID),
    CONSTRAINT FK_Drug_Manufacturer FOREIGN KEY (ManufacturerID) REFERENCES dbo.Manufacturer(ManufacturerID),
    CONSTRAINT FK_Drug_Unit FOREIGN KEY (UnitID) REFERENCES dbo.Unit(UnitID),

    CONSTRAINT UQ_Drug_Manufacturer_Name UNIQUE (ManufacturerID, Name)
);
GO

-- 1.8 Состав препарата (M:N)
CREATE TABLE dbo.DrugIngredient(
    DrugID INT NOT NULL,
    IngredientID INT NOT NULL,
    Amount DECIMAL(10,3) NOT NULL,
    AmountUnitID INT NOT NULL,

    CONSTRAINT PK_DrugIngredient PRIMARY KEY (DrugID, IngredientID),
    CONSTRAINT FK_DrugIngredient_Drug FOREIGN KEY (DrugID) REFERENCES dbo.Drug(DrugID) ON DELETE CASCADE,
    CONSTRAINT FK_DrugIngredient_Ingredient FOREIGN KEY (IngredientID) REFERENCES dbo.ActiveIngredient(IngredientID),
    CONSTRAINT FK_DrugIngredient_Unit FOREIGN KEY (AmountUnitID) REFERENCES dbo.Unit(UnitID),
    CONSTRAINT CHK_DrugIngredient_Amount CHECK (Amount > 0)
);
GO

-- 1.9 Поставщик ↔ препарат (что поставляет и по какой закуп. цене)
CREATE TABLE dbo.SupplierDrug(
    SupplierDrugID INT IDENTITY(1,1) CONSTRAINT PK_SupplierDrug PRIMARY KEY,
    SupplierID INT NOT NULL,
    DrugID INT NOT NULL,
    PurchasePrice MONEY NOT NULL,
    LeadTimeDays INT NOT NULL CONSTRAINT DF_SupplierDrug_Lead DEFAULT (3),
    IsActive BIT NOT NULL CONSTRAINT DF_SupplierDrug_Active DEFAULT (1),

    CONSTRAINT FK_SupplierDrug_Supplier FOREIGN KEY (SupplierID) REFERENCES dbo.Supplier(SupplierID),
    CONSTRAINT FK_SupplierDrug_Drug FOREIGN KEY (DrugID) REFERENCES dbo.Drug(DrugID),
    CONSTRAINT UQ_SupplierDrug UNIQUE (SupplierID, DrugID),
    CONSTRAINT CHK_SupplierDrug_Price CHECK (PurchasePrice > 0),
    CONSTRAINT CHK_SupplierDrug_Lead CHECK (LeadTimeDays > 0)
);
GO

-- 1.10 Партия (склад): срок годности, количество, розничная цена
CREATE TABLE dbo.Batch(
    BatchID INT IDENTITY(1,1) CONSTRAINT PK_Batch PRIMARY KEY,
    SupplierDrugID INT NOT NULL,
    BatchNumber NVARCHAR(50) NOT NULL,
    ExpirationDate DATE NOT NULL,
    ReceivedAt DATETIME2(0) NOT NULL CONSTRAINT DF_Batch_Received DEFAULT (SYSUTCDATETIME()),
    QtyReceived INT NOT NULL,
    QtyAvailable INT NOT NULL,
    RetailPrice MONEY NOT NULL,

    CONSTRAINT FK_Batch_SupplierDrug FOREIGN KEY (SupplierDrugID) REFERENCES dbo.SupplierDrug(SupplierDrugID),
    CONSTRAINT CHK_Batch_QtyReceived CHECK (QtyReceived > 0),
    CONSTRAINT CHK_Batch_QtyAvailable CHECK (QtyAvailable >= 0),
    CONSTRAINT CHK_Batch_RetailPrice CHECK (RetailPrice > 0)
);
GO

-- 1.11 Заказ поставщику
CREATE TABLE dbo.PurchaseOrder(
    PurchaseOrderID INT IDENTITY(1,1) CONSTRAINT PK_PurchaseOrder PRIMARY KEY,
    SupplierID INT NOT NULL,
    CreatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_PO_Created DEFAULT (SYSUTCDATETIME()),
    Status NVARCHAR(20) NOT NULL CONSTRAINT DF_PO_Status DEFAULT (N'New')
        CHECK (Status IN (N'New', N'Sent', N'Confirmed', N'Delivered', N'Cancelled')),
    Comment NVARCHAR(500) NULL,

    CONSTRAINT FK_PO_Supplier FOREIGN KEY (SupplierID) REFERENCES dbo.Supplier(SupplierID)
);
GO

-- 1.12 Позиция заказа
CREATE TABLE dbo.PurchaseOrderItem(
    PurchaseOrderItemID INT IDENTITY(1,1) CONSTRAINT PK_PurchaseOrderItem PRIMARY KEY,
    PurchaseOrderID INT NOT NULL,
    DrugID INT NOT NULL,
    QtyOrdered INT NOT NULL,
    PurchasePrice MONEY NOT NULL,

    CONSTRAINT FK_POI_PO FOREIGN KEY (PurchaseOrderID) REFERENCES dbo.PurchaseOrder(PurchaseOrderID) ON DELETE CASCADE,
    CONSTRAINT FK_POI_Drug FOREIGN KEY (DrugID) REFERENCES dbo.Drug(DrugID),
    CONSTRAINT CHK_POI_Qty CHECK (QtyOrdered > 0),
    CONSTRAINT CHK_POI_Price CHECK (PurchasePrice > 0),

    CONSTRAINT UQ_POI UNIQUE (PurchaseOrderID, DrugID)
);
GO

------------------------------------------------------------
-- 2. Д А Н Н Ы Е (тестовые)
------------------------------------------------------------

-- Страны
INSERT INTO dbo.Country(Name)
VALUES (N'Россия'), (N'Германия'), (N'Индия');
GO

-- Производители
INSERT INTO dbo.Manufacturer(Name, CountryID)
VALUES (N'ФармСтандарт', 1),
       (N'Bayer', 2),
       (N'Sun Pharma', 3);
GO

-- Поставщики
INSERT INTO dbo.Supplier(Name, INN, Phone, Email, Address)
VALUES (N'ООО "МедСнаб"', N'1234567890', N'+7 900 000-00-01', N'medsnab@test', N'Москва, ул. Пример, 1'),
       (N'ООО "Фарма-Логистик"', N'9876543210', N'+7 900 000-00-02', N'pharmalog@test', N'Москва, ул. Пример, 2');
GO

-- Единицы
INSERT INTO dbo.Unit(Name, ShortName)
VALUES (N'Упаковка', N'уп'), (N'Штука', N'шт'), (N'Миллиграмм', N'мг');
GO

-- Типы
INSERT INTO dbo.DrugType(Name)
VALUES (N'Таблетки'), (N'Капсулы'), (N'Сироп'), (N'Мазь');
GO

-- Вещества
INSERT INTO dbo.ActiveIngredient(Name)
VALUES (N'Ибупрофен'), (N'Парацетамол'), (N'Амоксициллин'), (N'Кетопрофен');
GO

-- Препараты
INSERT INTO dbo.Drug(Name, DrugTypeID, ManufacturerID, UnitID)
VALUES
(N'Ибупрофен 200', 1, 1, 1),
(N'Парацетамол 500', 1, 1, 1),
(N'Нурофен', 1, 2, 1),
(N'Амоксициллин 500', 2, 3, 1),
(N'Кетонал гель', 4, 2, 1);
GO

-- Состав (упрощенно: 1–2 вещества)
-- AmountUnitID = 3 (мг) для таблеток
INSERT INTO dbo.DrugIngredient(DrugID, IngredientID, Amount, AmountUnitID)
VALUES
(1, 1, 200, 3), -- Ибупрофен 200
(2, 2, 500, 3), -- Парацетамол 500
(3, 1, 200, 3), -- Нурофен (ибупрофен)
(4, 3, 500, 3); -- Амоксициллин 500
GO

-- Поставщик ↔ препарат
INSERT INTO dbo.SupplierDrug(SupplierID, DrugID, PurchasePrice, LeadTimeDays)
VALUES
(1, 1, 60, 2),
(1, 2, 50, 2),
(1, 3, 120, 3),
(2, 4, 180, 5),
(2, 5, 250, 4);
GO

-- Партии (сделаем так, чтобы у пары товаров остаток был < 10)
DECLARE @today DATE = CAST(GETDATE() AS DATE);

INSERT INTO dbo.Batch(SupplierDrugID, BatchNumber, ExpirationDate, QtyReceived, QtyAvailable, RetailPrice)
VALUES
(1, N'B-IBU-001', DATEADD(MONTH, 18, @today), 50, 8, 120),   -- остаток < 10
(2, N'B-PAR-001', DATEADD(MONTH, 12, @today), 40, 25, 110),
(3, N'B-NUR-001', DATEADD(MONTH, 20, @today), 30, 9, 220),   -- остаток < 10
(4, N'B-AMO-001', DATEADD(MONTH, 10, @today), 20, 15, 350),
(5, N'B-KET-001', DATEADD(MONTH, 24, @today), 15, 6, 500);   -- остаток < 10
GO

------------------------------------------------------------
-- 3. П Р Е Д С Т А В Л Е Н И Я (ровно 3)
------------------------------------------------------------

-- 3.1 Каталог лекарств (с производителем/страной/типом/единицей)
CREATE VIEW dbo.vDrugCatalog
AS
SELECT
    d.DrugID,
    d.Name AS DrugName,
    dt.Name AS DrugType,
    u.ShortName AS Unit,
    m.Name AS Manufacturer,
    c.Name AS Country,
    s.Name AS SupplierName,
    sd.PurchasePrice,
    -- Текущая минимальная розничная цена по складу (если есть партии)
    (SELECT MIN(b.RetailPrice)
     FROM dbo.Batch b
     WHERE b.SupplierDrugID = sd.SupplierDrugID) AS MinRetailPrice,
    (SELECT MIN(b.ExpirationDate)
     FROM dbo.Batch b
     WHERE b.SupplierDrugID = sd.SupplierDrugID) AS NearestExpiration
FROM dbo.Drug d
JOIN dbo.DrugType dt ON d.DrugTypeID = dt.DrugTypeID
JOIN dbo.Unit u ON d.UnitID = u.UnitID
JOIN dbo.Manufacturer m ON d.ManufacturerID = m.ManufacturerID
JOIN dbo.Country c ON m.CountryID = c.CountryID
LEFT JOIN dbo.SupplierDrug sd ON sd.DrugID = d.DrugID AND sd.IsActive = 1
LEFT JOIN dbo.Supplier s ON s.SupplierID = sd.SupplierID;
GO

-- 3.2 Остатки на складе по лекарствам
CREATE VIEW dbo.vStockByDrug
AS
SELECT
    d.DrugID,
    d.Name AS DrugName,
    SUM(b.QtyAvailable) AS StockQty
FROM dbo.Drug d
LEFT JOIN dbo.SupplierDrug sd ON sd.DrugID = d.DrugID
LEFT JOIN dbo.Batch b ON b.SupplierDrugID = sd.SupplierDrugID
GROUP BY d.DrugID, d.Name;
GO

-- 3.3 Список для дозакупки (остаток < 10 упаковок)
CREATE VIEW dbo.vReorderList
AS
SELECT
    v.DrugID,
    v.DrugName,
    v.StockQty
FROM dbo.vStockByDrug v
WHERE ISNULL(v.StockQty, 0) < 10;
GO

------------------------------------------------------------
-- 4. Ф У Н К Ц И И (ровно 3)
------------------------------------------------------------

-- 4.1 Остаток по лекарству (надёжно)
CREATE OR ALTER FUNCTION dbo.fn_StockQty (@DrugID INT)
RETURNS INT
AS
BEGIN
    DECLARE @Qty INT;

    SELECT @Qty = ISNULL(SUM(b.QtyAvailable), 0)
    FROM dbo.Batch b
    JOIN dbo.SupplierDrug sd ON sd.SupplierDrugID = b.SupplierDrugID
    WHERE sd.DrugID = @DrugID;

    RETURN ISNULL(@Qty, 0);
END;
GO

-- 4.2 Ближайшая партия (срок годности + остаток + цена + поставщик)
CREATE OR ALTER FUNCTION dbo.fn_NearestBatchInfo(@DrugID INT)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP(1)
        d.DrugID,
        d.Name AS DrugName,
        b.BatchID,
        b.BatchNumber,
        b.ExpirationDate,
        b.QtyAvailable,
        b.RetailPrice,
        s.Name AS SupplierName
    FROM dbo.Drug d
    JOIN dbo.SupplierDrug sd ON sd.DrugID = d.DrugID AND sd.IsActive = 1
    JOIN dbo.Supplier s ON s.SupplierID = sd.SupplierID
    JOIN dbo.Batch b ON b.SupplierDrugID = sd.SupplierDrugID
    WHERE d.DrugID = @DrugID
      AND b.QtyAvailable > 0
    ORDER BY b.ExpirationDate ASC
);
GO

-- 4.3 Аналоги по составу (ранжирование + процент совпадения)
CREATE OR ALTER FUNCTION dbo.fn_SimilarDrugs
(
    @DrugID INT,
    @TopN INT = 5
)
RETURNS TABLE
AS
RETURN
(
    WITH base_ing AS (
        SELECT IngredientID
        FROM dbo.DrugIngredient
        WHERE DrugID = @DrugID
    ),
    base_cnt AS (
        SELECT COUNT(*) AS Cnt FROM base_ing
    ),
    other_match AS (
        SELECT
            di.DrugID,
            COUNT(*) AS CommonIngredients
        FROM dbo.DrugIngredient di
        JOIN base_ing bi ON bi.IngredientID = di.IngredientID
        WHERE di.DrugID <> @DrugID
        GROUP BY di.DrugID
    )
    SELECT TOP(@TopN)
        d.DrugID,
        d.Name AS SimilarDrugName,
        om.CommonIngredients,
        CAST(100.0 * om.CommonIngredients / NULLIF(bc.Cnt,0) AS DECIMAL(5,1)) AS MatchPercent
    FROM other_match om
    CROSS JOIN base_cnt bc
    JOIN dbo.Drug d ON d.DrugID = om.DrugID
    ORDER BY om.CommonIngredients DESC, MatchPercent DESC, d.Name
);
GO

------------------------------------------------------------
-- 5. П Р О Ц Е Д У Р Ы (ровно 3)
------------------------------------------------------------

-- 5.1 Приход партии на склад (валидатор срока годности)
CREATE OR ALTER PROCEDURE dbo.sp_AddBatch
(
    @SupplierDrugID INT,
    @BatchNumber NVARCHAR(50),
    @ExpirationDate DATE,
    @QtyReceived INT,
    @RetailPrice MONEY,
    @BatchID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @QtyReceived <= 0
        THROW 51001, N'Количество должно быть > 0', 1;

    IF @RetailPrice <= 0
        THROW 51002, N'Розничная цена должна быть > 0', 1;

    IF @ExpirationDate <= CONVERT(date, GETDATE())
        THROW 51003, N'Нельзя принимать партию с истёкшим/сегодняшним сроком годности', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.SupplierDrug WHERE SupplierDrugID = @SupplierDrugID AND IsActive = 1)
        THROW 51004, N'SupplierDrugID не найден или не активен', 1;

    INSERT INTO dbo.Batch (SupplierDrugID, BatchNumber, ExpirationDate, ReceivedAt, QtyReceived, QtyAvailable, RetailPrice)
    VALUES (@SupplierDrugID, @BatchNumber, @ExpirationDate, SYSUTCDATETIME(), @QtyReceived, @QtyReceived, @RetailPrice);

    SET @BatchID = SCOPE_IDENTITY();
END;
GO

-- 5.2 Автосоздание заказов (остаток < 10) со статусом New (совместимо с CHECK)
CREATE OR ALTER PROCEDURE dbo.sp_CreateReorderOrders
(
    @MinQty INT = 10,
    @DefaultOrderQty INT = 25
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @NewPO TABLE (PurchaseOrderID INT, SupplierID INT);

        ;WITH Need AS
        (
            SELECT
                sd.SupplierID,
                sd.DrugID,
                sd.PurchasePrice
            FROM dbo.SupplierDrug sd
            WHERE sd.IsActive = 1
              AND dbo.fn_StockQty(sd.DrugID) < @MinQty
        )
        INSERT INTO dbo.PurchaseOrder (SupplierID, CreatedAt, Status, Comment)
        OUTPUT inserted.PurchaseOrderID, inserted.SupplierID
        INTO @NewPO (PurchaseOrderID, SupplierID)
        SELECT DISTINCT
            n.SupplierID,
            SYSUTCDATETIME(),
            N'New',
            N'Автозаказ: остаток ниже порога'
        FROM Need n;

        INSERT INTO dbo.PurchaseOrderItem (PurchaseOrderID, DrugID, QtyOrdered, PurchasePrice)
        SELECT
            po.PurchaseOrderID,
            n.DrugID,
            @DefaultOrderQty,
            n.PurchasePrice
        FROM Need n
        JOIN @NewPO po ON po.SupplierID = n.SupplierID;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

-- 5.3 Смена статуса заказа (только разрешённые статусы)
CREATE OR ALTER PROCEDURE dbo.sp_SetPurchaseOrderStatus
(
    @PurchaseOrderID INT,
    @NewStatus NVARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE PurchaseOrderID = @PurchaseOrderID)
        THROW 51020, N'Заказ не найден', 1;

    IF @NewStatus NOT IN (N'New', N'Sent', N'Confirmed', N'Delivered', N'Cancelled')
        THROW 51021, N'Недопустимый статус. Разрешено: New/Sent/Confirmed/Delivered/Cancelled', 1;

    UPDATE dbo.PurchaseOrder
    SET Status = @NewStatus
    WHERE PurchaseOrderID = @PurchaseOrderID;
END;
GO

------------------------------------------------------------
-- 6. Т Р И Г Г Е Р Ы (ровно 3)
------------------------------------------------------------

-- 6.1 Запрет прихода просроченной партии
CREATE TRIGGER dbo.TR_Batch_NoExpiredInsert
ON dbo.Batch
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.ExpirationDate < CAST(GETDATE() AS DATE)
    )
    BEGIN
        RAISERROR(N'Нельзя приходовать партию с просроченным сроком годности.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- 6.2 Контроль количества: QtyAvailable не может быть > QtyReceived и < 0
CREATE TRIGGER dbo.TR_Batch_QtyGuard
ON dbo.Batch
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.QtyAvailable < 0 OR i.QtyAvailable > i.QtyReceived
    )
    BEGIN
        RAISERROR(N'Ошибка количества: QtyAvailable должно быть в диапазоне [0..QtyReceived].', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- 6.3 При смене статуса заказа на Delivered — автоматически создаём партии на склад
CREATE TRIGGER dbo.TR_PO_OnDelivered_CreateBatch
ON dbo.PurchaseOrder
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(Status) RETURN;

    -- Срабатываем только на переход -> Delivered
    ;WITH Delivered AS (
        SELECT i.PurchaseOrderID
        FROM inserted i
        JOIN deleted d ON d.PurchaseOrderID = i.PurchaseOrderID
        WHERE i.Status = N'Delivered' AND d.Status <> N'Delivered'
    )
    INSERT INTO dbo.Batch(SupplierDrugID, BatchNumber, ExpirationDate, QtyReceived, QtyAvailable, RetailPrice)
    SELECT
        sd.SupplierDrugID,
        N'AUTO-PO-' + CONVERT(NVARCHAR(20), poi.PurchaseOrderID) + N'-D' + CONVERT(NVARCHAR(20), poi.DrugID),
        DATEADD(MONTH, 18, CAST(GETDATE() AS DATE)),        -- условный срок годности для демо
        poi.QtyOrdered,
        poi.QtyOrdered,
        CAST(poi.PurchasePrice * 1.8 AS MONEY)             -- условная розница для демо
    FROM Delivered x
    JOIN dbo.PurchaseOrderItem poi ON poi.PurchaseOrderID = x.PurchaseOrderID
    JOIN dbo.SupplierDrug sd ON sd.SupplierID = (SELECT SupplierID FROM dbo.PurchaseOrder WHERE PurchaseOrderID = x.PurchaseOrderID)
                           AND sd.DrugID = poi.DrugID
    WHERE sd.IsActive = 1;
END;
GO

/*==============================================================
  7. П Р О В Е Р К И  О Б Ъ Е К Т О В  Б Д
==============================================================*/

------------------------------------------------------------
-- 7.1 Проверка представлений
------------------------------------------------------------
PRINT '=== 7.1 Проверка представлений ===';
SELECT TOP(50) * FROM dbo.vDrugCatalog ORDER BY DrugID;
SELECT * FROM dbo.vStockByDrug ORDER BY DrugID;
SELECT * FROM dbo.vReorderList ORDER BY StockQty;
GO

------------------------------------------------------------
-- 7.2 Проверка функций
------------------------------------------------------------
PRINT '=== 7.2 Проверка функций ===';

SELECT TOP(10)
    d.DrugID,
    d.Name,
    dbo.fn_StockQty(d.DrugID) AS StockQty
FROM dbo.Drug d
ORDER BY d.DrugID;

SELECT TOP(10)
    BatchID,
    ExpirationDate,
    dbo.fn_BatchStatus(ExpirationDate) AS BatchStatus
FROM dbo.Batch
ORDER BY BatchID;

PRINT '=== Аналоги по составу (пример DrugID=1) ===';
SELECT * FROM dbo.fn_SimilarDrugs(1, 5);
GO

------------------------------------------------------------
-- 7.3 Проверка процедур
------------------------------------------------------------
PRINT '=== 7.3 Проверка процедур ===';

-- (1) sp_AddBatch
DECLARE @NewBatchID INT;
EXEC dbo.sp_AddBatch
    @SupplierDrugID = 2,
    @BatchNumber = N'B-PAR-002',
    @ExpirationDate = DATEADD(mm, 14, CONVERT(date, GETDATE())),
    @QtyReceived = 10,
    @RetailPrice = 115,
    @BatchID = @NewBatchID OUTPUT;

SELECT @NewBatchID AS NewBatchID;
SELECT * FROM dbo.Batch WHERE BatchID = @NewBatchID;
GO

-- (2) sp_CreateReorderOrders: создаст заказы на товары, где остаток < 10
EXEC dbo.sp_CreateReorderOrders @MinQty = 10, @DefaultOrderQty = 25;

SELECT TOP(10) * FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC;
SELECT TOP(50) * FROM dbo.PurchaseOrderItem ORDER BY PurchaseOrderItemID DESC;
GO

-- (3) sp_SetPurchaseOrderStatus + триггер авто-прихода
DECLARE @PO INT = (SELECT TOP(1) PurchaseOrderID FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC);
EXEC dbo.sp_SetPurchaseOrderStatus @PurchaseOrderID = @PO, @NewStatus = N'Delivered';

SELECT * FROM dbo.PurchaseOrder WHERE PurchaseOrderID = @PO;
SELECT TOP(50) b.*
FROM dbo.Batch b
ORDER BY b.BatchID DESC;
GO

------------------------------------------------------------
-- 7.4 Проверка триггеров
------------------------------------------------------------
PRINT '=== 7.4 Проверка триггеров ===';

-- TR_Batch_NoExpiredInsert: пробуем вставить просрочку (ожидаем ошибку)
BEGIN TRY
    INSERT INTO dbo.Batch(SupplierDrugID, BatchNumber, ExpirationDate, QtyReceived, QtyAvailable, RetailPrice)
    VALUES (1, N'B-TEST-EXPIRED', DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), 5, 5, 100);
END TRY
BEGIN CATCH
    PRINT N'Ожидаемая ошибка TR_Batch_NoExpiredInsert: ' + ERROR_MESSAGE();
END CATCH;
GO

-- TR_Batch_QtyGuard: пробуем QtyAvailable > QtyReceived (ожидаем ошибку)
BEGIN TRY
    UPDATE dbo.Batch SET QtyAvailable = QtyReceived + 1 WHERE BatchID = 1;
END TRY
BEGIN CATCH
    PRINT N'Ожидаемая ошибка TR_Batch_QtyGuard: ' + ERROR_MESSAGE();
END CATCH;
GO
