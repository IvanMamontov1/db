/* ===== PharmacyDB: schema (8 tables) ===== */

-- 0) Создать БД (если уже есть — можно пропустить этот блок)
IF DB_ID('PharmacyDB') IS NULL
    EXEC('CREATE DATABASE PharmacyDB');
GO

USE PharmacyDB;
GO

-- 1) Очистка (чтобы можно было запускать много раз)
IF OBJECT_ID('dbo.PurchaseOrderLines','U') IS NOT NULL DROP TABLE dbo.PurchaseOrderLines;
IF OBJECT_ID('dbo.PurchaseOrders','U') IS NOT NULL DROP TABLE dbo.PurchaseOrders;
IF OBJECT_ID('dbo.DrugSubstances','U') IS NOT NULL DROP TABLE dbo.DrugSubstances;
IF OBJECT_ID('dbo.ActiveSubstances','U') IS NOT NULL DROP TABLE dbo.ActiveSubstances;
IF OBJECT_ID('dbo.Batches','U') IS NOT NULL DROP TABLE dbo.Batches;
IF OBJECT_ID('dbo.SupplierDrugs','U') IS NOT NULL DROP TABLE dbo.SupplierDrugs;
IF OBJECT_ID('dbo.Suppliers','U') IS NOT NULL DROP TABLE dbo.Suppliers;
IF OBJECT_ID('dbo.Drugs','U') IS NOT NULL DROP TABLE dbo.Drugs;
GO

/* 2) Таблицы */

-- 1 Drugs
CREATE TABLE dbo.Drugs(
  DrugId int IDENTITY(1,1) PRIMARY KEY,
  Name nvarchar(200) NOT NULL,
  DrugType nvarchar(80) NOT NULL,
  Unit nvarchar(20) NOT NULL,
  RetailPrice decimal(12,2) NOT NULL CHECK (RetailPrice >= 0),
  Country nvarchar(80) NULL,
  Manufacturer nvarchar(120) NULL,
  IsActive bit NOT NULL DEFAULT(1)
);
GO

-- 2 Suppliers
CREATE TABLE dbo.Suppliers(
  SupplierId int IDENTITY(1,1) PRIMARY KEY,
  Name nvarchar(200) NOT NULL,
  Phone nvarchar(30) NULL,
  Email nvarchar(100) NULL,
  Inn nvarchar(12) NULL UNIQUE,
  IsActive bit NOT NULL DEFAULT(1)
);
GO

-- 3 SupplierDrugs (каталог)
CREATE TABLE dbo.SupplierDrugs(
  SupplierId int NOT NULL,
  DrugId int NOT NULL,
  SupplierPrice decimal(12,2) NOT NULL CHECK (SupplierPrice >= 0),
  LeadDays int NOT NULL DEFAULT(3) CHECK (LeadDays >= 0),
  CONSTRAINT PK_SupplierDrugs PRIMARY KEY (SupplierId, DrugId),
  CONSTRAINT FK_SD_Supplier FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers(SupplierId),
  CONSTRAINT FK_SD_Drug FOREIGN KEY (DrugId) REFERENCES dbo.Drugs(DrugId)
);
GO

-- 4 Batches (партии/склад)
CREATE TABLE dbo.Batches(
  BatchId int IDENTITY(1,1) PRIMARY KEY,
  DrugId int NOT NULL,
  SupplierId int NOT NULL,
  BatchNo nvarchar(50) NOT NULL,
  ExpiryDate date NOT NULL,
  PurchasePrice decimal(12,2) NOT NULL CHECK (PurchasePrice >= 0),
  Quantity int NOT NULL CHECK (Quantity >= 0),
  CONSTRAINT FK_B_Drug FOREIGN KEY (DrugId) REFERENCES dbo.Drugs(DrugId),
  CONSTRAINT FK_B_Supplier FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers(SupplierId)
);
GO

-- 5 ActiveSubstances
CREATE TABLE dbo.ActiveSubstances(
  SubstanceId int IDENTITY(1,1) PRIMARY KEY,
  Name nvarchar(200) NOT NULL UNIQUE
);
GO

-- 6 DrugSubstances (состав)
CREATE TABLE dbo.DrugSubstances(
  DrugId int NOT NULL,
  SubstanceId int NOT NULL,
  Dosage decimal(12,4) NOT NULL CHECK (Dosage > 0),
  DosageUnit nvarchar(20) NOT NULL,
  CONSTRAINT PK_DrugSubstances PRIMARY KEY (DrugId, SubstanceId),
  CONSTRAINT FK_DS_Drug FOREIGN KEY (DrugId) REFERENCES dbo.Drugs(DrugId),
  CONSTRAINT FK_DS_Substance FOREIGN KEY (SubstanceId) REFERENCES dbo.ActiveSubstances(SubstanceId)
);
GO

-- 7 PurchaseOrders (заказы)
CREATE TABLE dbo.PurchaseOrders(
  OrderId bigint IDENTITY(1,1) PRIMARY KEY,
  SupplierId int NOT NULL,
  CreatedAt datetime2 NOT NULL DEFAULT sysdatetime(),
  Status nvarchar(20) NOT NULL CHECK (Status IN ('NEW','SENT','PARTIAL','DONE','CANCELED')),
  Comment nvarchar(500) NULL,
  CONSTRAINT FK_PO_Supplier FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers(SupplierId)
);
GO

-- 8 PurchaseOrderLines (строки заказов)
CREATE TABLE dbo.PurchaseOrderLines(
  OrderId bigint NOT NULL,
  [LineNo] int NOT NULL,
  DrugId int NOT NULL,
  Qty int NOT NULL CHECK (Qty > 0),
  UnitPrice decimal(12,2) NOT NULL CHECK (UnitPrice >= 0),

  CONSTRAINT PK_PurchaseOrderLines PRIMARY KEY (OrderId, [LineNo]),
  CONSTRAINT UQ_PurchaseOrderLines UNIQUE (OrderId, DrugId),
  CONSTRAINT FK_POL_Order FOREIGN KEY (OrderId) REFERENCES dbo.PurchaseOrders(OrderId),
  CONSTRAINT FK_POL_Drug FOREIGN KEY (DrugId) REFERENCES dbo.Drugs(DrugId)
);
GO

-- 3) Проверка
SELECT name FROM sys.tables ORDER BY name;
GO
