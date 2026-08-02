
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `compound_check` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `balance` decimal(16, 2) NOT NULL CHECK (balance >= 0 AND balance <= 99999),
  `score` int NOT NULL CHECK (score > 0 AND score <= 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
