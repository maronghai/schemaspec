
CREATE TABLE [user] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL /* 用户登录名 */,
  [email] NVARCHAR(128) NOT NULL /* 唯一邮箱 */,
  [password] NVARCHAR(256) NOT NULL /* bcrypt hash */,
  [avatar] NVARCHAR(MAX) NOT NULL /* 头像 URL */,
  [is_admin] BIT NOT NULL DEFAULT 0 /* 管理员标记 */,
  [balance] NUMERIC(16, 2) NOT NULL DEFAULT 0 /* 账户余额（分） */,
  [settings] NVARCHAR(MAX) NOT NULL /* JSON 用户偏好 */,
  [version] BIGINT NOT NULL,
  [status] INT NOT NULL DEFAULT 0,
  [delete_at] DATETIME2 NOT NULL,
  [create_at] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  [update_at] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE [uk_email] ([email]),
  INDEX [idx_name] ([name])
);

CREATE TABLE [product] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(128) NOT NULL /* 商品名称 */,
  [description] NVARCHAR(MAX) NOT NULL /* 商品详情 */,
  [price] NUMERIC(16, 2) NOT NULL /* 单价（分） */,
  [stock] INT NOT NULL DEFAULT 0 /* 库存数量 */,
  [category_id] INT NOT NULL /* 分类 ID */,
  [version] BIGINT NOT NULL,
  [status] INT NOT NULL DEFAULT 0,
  [delete_at] DATETIME2 NOT NULL,
  [create_at] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  [update_at] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX [idx_category_id] ([category_id]),
  INDEX [idx_price] ([price])
);

CREATE TABLE [order] (
  [id] INT NOT NULL PRIMARY KEY,
  [order_no] NVARCHAR(64) NOT NULL /* 唯一订单号 */,
  [user_id] INT NOT NULL /* 下单用户 */,
  [amount] NUMERIC(16, 2) NOT NULL /* 订单总额（分） */,
  [discount] NUMERIC(20, 6) NOT NULL DEFAULT 0 /* 折扣金额（分） */,
  [note] NVARCHAR(512) NOT NULL /* 买家留言 */,
  [paid_on] DATE NOT NULL /* 支付日期 */,
  [version] BIGINT NOT NULL,
  [status] INT NOT NULL DEFAULT 0,
  [delete_at] DATETIME2 NOT NULL,
  [create_at] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  [update_at] DATETIME2 NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE [uk_order_no] ([order_no]),
  INDEX [idx_user_id] ([user_id]),
  INDEX [idx_paid_on] ([paid_on]),
  FOREIGN KEY ([user_id]) REFERENCES [user]([id])
);
