
CREATE DATABASE `ecommerce` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL COMMENT '用户登录名',
  `email` varchar(128) NOT NULL COMMENT '唯一邮箱',
  `password` varchar(256) NOT NULL COMMENT 'bcrypt hash',
  `avatar` text NOT NULL COMMENT '头像 URL',
  `is_admin` boolean NOT NULL DEFAULT 0 COMMENT '管理员标记',
  `balance` decimal(16, 2) NOT NULL DEFAULT 0 COMMENT '账户余额（分）',
  `settings` json NOT NULL COMMENT 'JSON 用户偏好',
  `version` bigint NOT NULL,
  `status` int NOT NULL DEFAULT 0,
  `delete_at` datetime NOT NULL,
  `create_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `update_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE INDEX `uk_email` (`email`),
  INDEX `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

CREATE TABLE `product` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(128) NOT NULL COMMENT '商品名称',
  `description` text NOT NULL COMMENT '商品详情',
  `price` decimal(16, 2) NOT NULL COMMENT '单价（分）',
  `stock` int NOT NULL DEFAULT 0 COMMENT '库存数量',
  `category_id` int NOT NULL COMMENT '分类 ID',
  `version` bigint NOT NULL,
  `status` int NOT NULL DEFAULT 0,
  `delete_at` datetime NOT NULL,
  `create_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `update_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_category_id` (`category_id`),
  INDEX `idx_price` (`price`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表';

CREATE TABLE `order` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `order_no` varchar(64) NOT NULL COMMENT '唯一订单号',
  `user_id` int NOT NULL COMMENT '下单用户',
  `amount` decimal(16, 2) NOT NULL COMMENT '订单总额（分）',
  `discount` decimal(20, 6) NOT NULL DEFAULT 0 COMMENT '折扣金额（分）',
  `note` varchar(512) NOT NULL COMMENT '买家留言',
  `paid_on` date NOT NULL COMMENT '支付日期',
  `version` bigint NOT NULL,
  `status` int NOT NULL DEFAULT 0,
  `delete_at` datetime NOT NULL,
  `create_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `update_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE INDEX `uk_order_no` (`order_no`),
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_paid_on` (`paid_on`),
  FOREIGN KEY (`user_id`) REFERENCES `user`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单表';
