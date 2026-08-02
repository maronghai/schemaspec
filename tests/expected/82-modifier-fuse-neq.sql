
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL DEFAULT 0,
  `email` varchar(128) NOT NULL,
  `is_active` boolean NOT NULL DEFAULT 1,
  `status` int NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
  `balance` decimal(16, 2) NOT NULL DEFAULT 0.00,
  `role` varchar(32) NOT NULL DEFAULT 'admin'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
