
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `order` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` int NOT NULL,
  `amount` decimal(16, 2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE OR REPLACE VIEW `user_summary` AS
SELECT u.id, u.name, COUNT(o.id) AS order_count FROM user u LEFT JOIN order o ON u.id = o.user_id GROUP BY u.id;

CREATE OR REPLACE VIEW `expensive_orders` AS
SELECT FROM order WHERE amount > 1000;
