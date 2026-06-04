/*==============================================================
  PharmacyDB (Вариант 19): Информационная поддержка аптеки
  Требования:
  - Таблицы >= 10 (здесь 12)
  - РОВНО: 3 VIEW, 3 FUNCTION, 3 PROC, 3 TRIGGER
  - 3НФ: справочники вынесены, M:N через связующую таблицу
==============================================================*/

------------------------------------------------------------
-- 0) Пересоздание БД
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
-- 1) Таблицы (12 шт.)
------------------------------------------------------------

-- 1.1 Страна
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
    CONSTRAINT FK_Manufacturer_Country FOREIGN KEY (CountryID) REFERENCES dbo.Country(CountryID),
    CONSTRAINT UQ_Manufacturer UNIQUE (Name, CountryID)
);
GO

-- 1.3 Поставщик
CREATE TABLE dbo.Supplier(
    SupplierID INT IDENTITY(1,1) CONSTRAINT PK_Supplier PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    INN NVARCHAR(20) NULL,
    Phone NVARCHAR(50) NULL,
    Email NVARCHAR(255) NULL,
    Address NVARCHAR(255) NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_Supplier_IsActive DEFAULT(1)
);
GO

-- 1.4 Единицы измерения
CREATE TABLE dbo.Unit(
    UnitID INT IDENTITY(1,1) CONSTRAINT PK_Unit PRIMARY KEY,
    Name NVARCHAR(80) NOT NULL,
    ShortName NVARCHAR(20) NOT NULL CONSTRAINT UQ_Unit_Short UNIQUE
);
GO

-- 1.5 Тип лекарства
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

-- 1.7 Лекарство (карточка)
CREATE TABLE dbo.Drug(
    DrugID INT IDENTITY(1,1) CONSTRAINT PK_Drug PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    DrugTypeID INT NOT NULL,
    ManufacturerID INT NOT NULL,
    UnitID INT NOT NULL,
    RequiresPrescription BIT NOT NULL CONSTRAINT DF_Drug_Rx DEFAULT(0),

    CONSTRAINT FK_Drug_DrugType FOREIGN KEY (DrugTypeID) REFERENCES dbo.DrugType(DrugTypeID),
    CONSTRAINT FK_Drug_Manufacturer FOREIGN KEY (ManufacturerID) REFERENCES dbo.Manufacturer(ManufacturerID),
    CONSTRAINT FK_Drug_Unit FOREIGN KEY (UnitID) REFERENCES dbo.Unit(UnitID),
    CONSTRAINT UQ_Drug_Manufacturer_Name UNIQUE (ManufacturerID, Name)
);
GO

-- 1.8 Состав (M:N)
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

-- 1.9 Поставщик-препарат (что поставляет и цена закупки)
CREATE TABLE dbo.SupplierDrug(
    SupplierDrugID INT IDENTITY(1,1) CONSTRAINT PK_SupplierDrug PRIMARY KEY,
    SupplierID INT NOT NULL,
    DrugID INT NOT NULL,
    PurchasePrice MONEY NOT NULL,
    LeadTimeDays INT NOT NULL CONSTRAINT DF_SupplierDrug_Lead DEFAULT(3),
    IsActive BIT NOT NULL CONSTRAINT DF_SupplierDrug_Active DEFAULT(1),

    CONSTRAINT FK_SupplierDrug_Supplier FOREIGN KEY (SupplierID) REFERENCES dbo.Supplier(SupplierID),
    CONSTRAINT FK_SupplierDrug_Drug FOREIGN KEY (DrugID) REFERENCES dbo.Drug(DrugID),
    CONSTRAINT UQ_SupplierDrug UNIQUE (SupplierID, DrugID),
    CONSTRAINT CHK_SupplierDrug_Price CHECK (PurchasePrice > 0),
    CONSTRAINT CHK_SupplierDrug_Lead CHECK (LeadTimeDays > 0)
);
GO

-- 1.10 Партии на складе
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
    Status NVARCHAR(20) NOT NULL CONSTRAINT DF_PO_Status DEFAULT(N'New')
        CHECK (Status IN (N'New', N'Sent', N'Confirmed', N'Delivered', N'Cancelled')),
    Comment NVARCHAR(500) NULL,

    CONSTRAINT FK_PO_Supplier FOREIGN KEY (SupplierID) REFERENCES dbo.Supplier(SupplierID)
);
GO

-- 1.12 Позиции заказа
CREATE TABLE dbo.PurchaseOrderItem(
    PurchaseOrderItemID INT IDENTITY(1,1) CONSTRAINT PK_PurchaseOrderItem PRIMARY KEY,
    PurchaseOrderID INT NOT NULL,
    DrugID INT NOT NULL,
    QtyOrdered INT NOT NULL,
    PurchasePrice MONEY NOT NULL,

    CONSTRAINT FK_POI_PO FOREIGN KEY (PurchaseOrderID) REFERENCES dbo.PurchaseOrder(PurchaseOrderID) ON DELETE CASCADE,
    CONSTRAINT FK_POI_Drug FOREIGN KEY (DrugID) REFERENCES dbo.Drug(DrugID),
    CONSTRAINT UQ_POI UNIQUE (PurchaseOrderID, DrugID),
    CONSTRAINT CHK_POI_Qty CHECK (QtyOrdered > 0),
    CONSTRAINT CHK_POI_Price CHECK (PurchasePrice > 0)
);
GO

------------------------------------------------------------
-- 2) Тестовые данные
------------------------------------------------------------
INSERT INTO dbo.Country(Name) VALUES (N'Россия'),(N'Германия'),(N'Индия');
GO

INSERT INTO dbo.Manufacturer(Name, CountryID)
VALUES (N'ФармСтандарт',1),(N'Bayer',2),(N'Sun Pharma',3);
GO

INSERT INTO dbo.Supplier(Name, INN, Phone, Email, Address)
VALUES
(N'ООО "МедСнаб"', N'1234567890', N'+7 900 000-00-01', N'medsnab@test', N'Москва, ул. Пример, 1'),
(N'ООО "Фарма-Логистик"', N'9876543210', N'+7 900 000-00-02', N'pharmalog@test', N'Москва, ул. Пример, 2');
GO

INSERT INTO dbo.Unit(Name, ShortName)
VALUES (N'Упаковка',N'уп'),(N'Штука',N'шт'),(N'Миллиграмм',N'мг');
GO

INSERT INTO dbo.DrugType(Name)
VALUES (N'Таблетки'),(N'Капсулы'),(N'Сироп'),(N'Мазь');
GO

INSERT INTO dbo.ActiveIngredient(Name)
VALUES (N'Ибупрофен'),(N'Парацетамол'),(N'Амоксициллин'),(N'Кетопрофен');
GO

INSERT INTO dbo.Drug(Name, DrugTypeID, ManufacturerID, UnitID, RequiresPrescription)
VALUES
(N'Ибупрофен 200', 1, 1, 1, 0),
(N'Парацетамол 500', 1, 1, 1, 0),
(N'Нурофен', 1, 2, 1, 0),
(N'Амоксициллин 500', 2, 3, 1, 1),
(N'Кетонал гель', 4, 2, 1, 0);
GO

INSERT INTO dbo.DrugIngredient(DrugID, IngredientID, Amount, AmountUnitID)
VALUES
(1,1,200,3),
(2,2,500,3),
(3,1,200,3),
(4,3,500,3),
(5,4,50,3);
GO

INSERT INTO dbo.SupplierDrug(SupplierID, DrugID, PurchasePrice, LeadTimeDays)
VALUES
(1,1,60,2),
(1,2,50,2),
(1,3,120,3),
(2,4,180,5),
(2,5,250,4);
GO

DECLARE @today DATE = CAST(GETDATE() AS DATE);

-- делаем остатки так, чтобы были < 10
INSERT INTO dbo.Batch(SupplierDrugID, BatchNumber, ExpirationDate, QtyReceived, QtyAvailable, RetailPrice)
VALUES
(1, N'B-IBU-001', DATEADD(MONTH, 18, @today), 50, 8, 120),
(2, N'B-PAR-001', DATEADD(MONTH, 12, @today), 40, 25, 110),
(3, N'B-NUR-001', DATEADD(MONTH, 20, @today), 30, 9, 220),
(4, N'B-AMO-001', DATEADD(MONTH, 10, @today), 20, 15, 350),
(5, N'B-KET-001', DATEADD(MONTH, 24, @today), 15, 6, 500);
GO

------------------------------------------------------------
-- 3) VIEW (ровно 3)
------------------------------------------------------------

-- V1: Каталог лекарств (19.1)
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
    MIN(b.RetailPrice) AS MinRetailPrice,
    MIN(b.ExpirationDate) AS NearestExpiration
FROM dbo.Drug d
JOIN dbo.DrugType dt ON dt.DrugTypeID = d.DrugTypeID
JOIN dbo.Unit u ON u.UnitID = d.UnitID
JOIN dbo.Manufacturer m ON m.ManufacturerID = d.ManufacturerID
JOIN dbo.Country c ON c.CountryID = m.CountryID
LEFT JOIN dbo.SupplierDrug sd ON sd.DrugID = d.DrugID AND sd.IsActive = 1
LEFT JOIN dbo.Supplier s ON s.SupplierID = sd.SupplierID
LEFT JOIN dbo.Batch b ON b.SupplierDrugID = sd.SupplierDrugID AND b.QtyAvailable > 0
GROUP BY
    d.DrugID, d.Name, dt.Name, u.ShortName, m.Name, c.Name, s.Name, sd.PurchasePrice;
GO

-- V2: Остатки по лекарствам (19.3)
CREATE VIEW dbo.vStockByDrug
AS
SELECT
    d.DrugID,
    d.Name AS DrugName,
    ISNULL(SUM(b.QtyAvailable), 0) AS StockQty
FROM dbo.Drug d
LEFT JOIN dbo.SupplierDrug sd ON sd.DrugID = d.DrugID AND sd.IsActive = 1
LEFT JOIN dbo.Batch b ON b.SupplierDrugID = sd.SupplierDrugID
GROUP BY d.DrugID, d.Name;
GO

-- V3: Список к дозакупке (остаток < 10) (19.4)
CREATE VIEW dbo.vReorderList
AS
SELECT DrugID, DrugName, StockQty
FROM dbo.vStockByDrug
WHERE StockQty < 10;
GO

------------------------------------------------------------
-- 4) FUNCTION (ровно 3)
------------------------------------------------------------

-- F1: Остаток по лекарству (используется везде)
CREATE OR ALTER FUNCTION dbo.fn_StockQty(@DrugID INT)
RETURNS INT
AS
BEGIN
    DECLARE @Qty INT;

    SELECT @Qty = ISNULL(SUM(b.QtyAvailable), 0)
    FROM dbo.Batch b
    JOIN dbo.SupplierDrug sd ON sd.SupplierDrugID = b.SupplierDrugID
    WHERE sd.IsActive = 1
      AND sd.DrugID = @DrugID;

    RETURN ISNULL(@Qty, 0);
END;
GO

-- F2: Минимальная розничная цена по доступным партиям
CREATE OR ALTER FUNCTION dbo.fn_MinRetailPrice(@DrugID INT)
RETURNS MONEY
AS
BEGIN
    DECLARE @P MONEY;

    SELECT @P = MIN(b.RetailPrice)
    FROM dbo.Batch b
    JOIN dbo.SupplierDrug sd ON sd.SupplierDrugID = b.SupplierDrugID
    WHERE sd.IsActive = 1
      AND sd.DrugID = @DrugID
      AND b.QtyAvailable > 0
      AND b.ExpirationDate > CAST(GETDATE() AS DATE);

    RETURN ISNULL(@P, 0);
END;
GO

-- F3: Аналоги по составу (19.2) — ранжирование + % совпадения
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
-- 5) PROCEDURE (ровно 3)
------------------------------------------------------------

-- P1: Приход партии (валидатор)
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
        THROW 51002, N'Цена должна быть > 0', 1;

    IF @ExpirationDate <= CONVERT(date, GETDATE())
        THROW 51003, N'Нельзя принимать партию с истёкшим/сегодняшним сроком годности', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.SupplierDrug WHERE SupplierDrugID = @SupplierDrugID AND IsActive = 1)
        THROW 51004, N'SupplierDrugID не найден или не активен', 1;

    INSERT INTO dbo.Batch (SupplierDrugID, BatchNumber, ExpirationDate, ReceivedAt, QtyReceived, QtyAvailable, RetailPrice)
    VALUES (@SupplierDrugID, @BatchNumber, @ExpirationDate, SYSUTCDATETIME(), @QtyReceived, @QtyReceived, @RetailPrice);

    SET @BatchID = SCOPE_IDENTITY();
END;
GO

-- P2: Автосоздание заказов (остаток < @MinQty) (19.4)
-- (фикс бага "Need": CTE используется ДВА раза => делаем через #Need)
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

        -- ВАЖНО: CTE нельзя использовать 2 раза подряд в разных INSERT
        -- поэтому сохраняем Need во временную таблицу
        IF OBJECT_ID('tempdb..#Need') IS NOT NULL DROP TABLE #Need;

        SELECT
            sd.SupplierID,
            sd.DrugID,
            sd.PurchasePrice
        INTO #Need
        FROM dbo.SupplierDrug sd
        WHERE sd.IsActive = 1
          AND dbo.fn_StockQty(sd.DrugID) < @MinQty;

        -- если нечего заказывать
        IF NOT EXISTS (SELECT 1 FROM #Need)
        BEGIN
            COMMIT TRAN;
            RETURN;
        END

        DECLARE @NewPO TABLE (PurchaseOrderID INT, SupplierID INT);

        -- 1) создаём заказы по поставщикам
        INSERT INTO dbo.PurchaseOrder (SupplierID, CreatedAt, Status, Comment)
        OUTPUT inserted.PurchaseOrderID, inserted.SupplierID INTO @NewPO (PurchaseOrderID, SupplierID)
        SELECT DISTINCT
            n.SupplierID,
            SYSUTCDATETIME(),
            N'New',
            N'Автозаказ: остаток ниже порога'
        FROM #Need n;

        -- 2) добавляем позиции
        INSERT INTO dbo.PurchaseOrderItem (PurchaseOrderID, DrugID, QtyOrdered, PurchasePrice)
        SELECT
            po.PurchaseOrderID,
            n.DrugID,
            @DefaultOrderQty,
            n.PurchasePrice
        FROM #Need n
        JOIN @NewPO po ON po.SupplierID = n.SupplierID;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

-- P3: Смена статуса заказа (19.5)
CREATE OR ALTER PROCEDURE dbo.sp_SetPurchaseOrderStatus
(
    @PurchaseOrderID INT,
    @NewStatus NVARCHAR(20)
)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE PurchaseOrderID = @PurchaseOrderID)
        THROW 52001, N'Заказ не найден', 1;

    IF @NewStatus NOT IN (N'New', N'Sent', N'Confirmed', N'Delivered', N'Cancelled')
        THROW 52002, N'Недопустимый статус. Разрешено: New/Sent/Confirmed/Delivered/Cancelled', 1;

    UPDATE dbo.PurchaseOrder
    SET Status = @NewStatus
    WHERE PurchaseOrderID = @PurchaseOrderID;
END;
GO

------------------------------------------------------------
-- 6) TRIGGER (ровно 3)
------------------------------------------------------------

-- T1: Запрет просроченной партии
CREATE TRIGGER dbo.TR_Batch_NoExpiredInsert
ON dbo.Batch
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted WHERE ExpirationDate <= CAST(GETDATE() AS DATE))
    BEGIN
        RAISERROR(N'Нельзя приходовать партию с истёкшим/сегодняшним сроком годности.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- T2: Контроль QtyAvailable в диапазоне [0..QtyReceived]
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

-- T3: При переводе заказа в Delivered — создаём партии на склад (демо логика)
CREATE TRIGGER dbo.TR_PO_OnDelivered_CreateBatch
ON dbo.PurchaseOrder
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Status) RETURN;

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
        DATEADD(MONTH, 18, CAST(GETDATE() AS DATE)),
        poi.QtyOrdered,
        poi.QtyOrdered,
        CAST(poi.PurchasePrice * 1.8 AS MONEY)
    FROM Delivered x
    JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID = x.PurchaseOrderID
    JOIN dbo.PurchaseOrderItem poi ON poi.PurchaseOrderID = x.PurchaseOrderID
    JOIN dbo.SupplierDrug sd ON sd.SupplierID = po.SupplierID AND sd.DrugID = poi.DrugID
    WHERE sd.IsActive = 1;
END;
GO

/*==============================================================
  7) ПРОВЕРКИ (View / Function / Proc / Trigger) + Критерии 19.1–19.6
  На защите показывай ВОТ ЭТОТ БЛОК.
==============================================================*/

PRINT N'=== A) Проверка VIEW ===';
SELECT TOP(50) * FROM dbo.vDrugCatalog ORDER BY DrugName;
SELECT * FROM dbo.vStockByDrug ORDER BY DrugID;
SELECT * FROM dbo.vReorderList ORDER BY StockQty;

PRINT N'=== B) Проверка FUNCTION ===';
SELECT TOP(10)
    d.DrugID,
    d.Name,
    dbo.fn_StockQty(d.DrugID) AS StockQty,
    dbo.fn_MinRetailPrice(d.DrugID) AS MinRetailPrice
FROM dbo.Drug d
ORDER BY d.DrugID;

DECLARE @DrugForAnalog INT = (SELECT TOP(1) DrugID FROM dbo.Drug ORDER BY DrugID);
PRINT N'=== Аналоги по составу (пример) ===';
SELECT * FROM dbo.fn_SimilarDrugs(@DrugForAnalog, 5);

PRINT N'=== C) Проверка PROCEDURE ===';
-- C1 sp_AddBatch (добавим новую партию)
DECLARE @NewBatchID INT;
EXEC dbo.sp_AddBatch
    @SupplierDrugID = 2,
    @BatchNumber = N'B-PAR-002',
    @ExpirationDate = DATEADD(MONTH ,14, CONVERT(date, GETDATE())),
    @QtyReceived = 10,
    @RetailPrice = 115,
    @BatchID = @NewBatchID OUTPUT;
SELECT @NewBatchID AS NewBatchID;
SELECT * FROM dbo.Batch WHERE BatchID = @NewBatchID;

-- C2 sp_CreateReorderOrders (создаст заказы на то, где остаток < 10)
EXEC dbo.sp_CreateReorderOrders @MinQty = 10, @DefaultOrderQty = 25;
SELECT TOP(10) * FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC;
SELECT TOP(50) * FROM dbo.PurchaseOrderItem ORDER BY PurchaseOrderItemID DESC;

-- C3 sp_SetPurchaseOrderStatus + триггер прихода партий
DECLARE @PO INT = (SELECT TOP(1) PurchaseOrderID FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC);
EXEC dbo.sp_SetPurchaseOrderStatus @PurchaseOrderID = @PO, @NewStatus = N'Delivered';
SELECT * FROM dbo.PurchaseOrder WHERE PurchaseOrderID = @PO;
SELECT TOP(20) * FROM dbo.Batch ORDER BY BatchID DESC;

PRINT N'=== D) Проверка TRIGGER (ожидаемые ошибки) ===';

-- D1 TR_Batch_NoExpiredInsert: пробуем вставить просрочку (ожидаем ошибку)
BEGIN TRY
    INSERT INTO dbo.Batch(SupplierDrugID, BatchNumber, ExpirationDate, QtyReceived, QtyAvailable, RetailPrice)
    VALUES (1, N'B-TEST-EXPIRED', DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), 5, 5, 100);
END TRY
BEGIN CATCH
    PRINT N'Ожидаемая ошибка TR_Batch_NoExpiredInsert: ' + ERROR_MESSAGE();
END CATCH;

-- D2 TR_Batch_QtyGuard: пробуем QtyAvailable > QtyReceived (ожидаем ошибку)
BEGIN TRY
    UPDATE dbo.Batch SET QtyAvailable = QtyReceived + 1 WHERE BatchID = 1;
END TRY
BEGIN CATCH
    PRINT N'Ожидаемая ошибка TR_Batch_QtyGuard: ' + ERROR_MESSAGE();
END CATCH;

PRINT N'=== E) Вариант 19: проверка критериев (19.1–19.6) ===';

-- 19.1 Информация о лекарствах (название, тип, кол-во, ед, цена, страна, поставщик, срок)
PRINT N'--- 19.1 Каталог лекарств ---';
SELECT
    c.DrugID,
    c.DrugName,
    c.DrugType,
    c.Unit,
    dbo.fn_StockQty(c.DrugID) AS StockQty,
    dbo.fn_MinRetailPrice(c.DrugID) AS MinRetailPrice,
    c.Country,
    c.Manufacturer,
    c.SupplierName,
    c.NearestExpiration
FROM dbo.vDrugCatalog c
ORDER BY c.DrugName;

-- 19.2 Аналоги по составу
PRINT N'--- 19.2 Аналоги по составу ---';
DECLARE @NeedAnalogDrug INT = (SELECT TOP(1) DrugID FROM dbo.Drug ORDER BY DrugID);
SELECT * FROM dbo.fn_SimilarDrugs(@NeedAnalogDrug, 5);

-- 19.3 Остатки на складе
PRINT N'--- 19.3 Остатки ---';
SELECT * FROM dbo.vStockByDrug ORDER BY StockQty;

-- 19.4 Формирование заказов на лекарства, где остаток < 10
PRINT N'--- 19.4 Список к заказу ---';
SELECT * FROM dbo.vReorderList ORDER BY StockQty;

PRINT N'--- 19.4 Создание автозаказов ---';
EXEC dbo.sp_CreateReorderOrders @MinQty = 10, @DefaultOrderQty = 25;
SELECT TOP(10) * FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC;

-- 19.5 Отслеживание выполнения заказов поставщиками
PRINT N'--- 19.5 Отслеживание заказа (демо статус) ---';
DECLARE @PO2 INT = (SELECT TOP(1) PurchaseOrderID FROM dbo.PurchaseOrder ORDER BY PurchaseOrderID DESC);
EXEC dbo.sp_SetPurchaseOrderStatus @PurchaseOrderID = @PO2, @NewStatus = N'Confirmed';
EXEC dbo.sp_SetPurchaseOrderStatus @PurchaseOrderID = @PO2, @NewStatus = N'Delivered';
SELECT * FROM dbo.PurchaseOrder WHERE PurchaseOrderID = @PO2;
SELECT TOP(20) * FROM dbo.Batch ORDER BY BatchID DESC;

-- 19.6 Учет поставщиков
PRINT N'--- 19.6 Поставщики ---';
SELECT * FROM dbo.Supplier ORDER BY SupplierID;

PRINT N'=== Конец демонстрации ===';
GO
