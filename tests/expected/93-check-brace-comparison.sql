
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `amount` decimal(16, 2) NOT NULL CHECK (amount > 0),
  `ratio` decimal(20, 6) NOT NULL CHECK (ratio >= 0 AND ratio <= 100),
  `score` int NOT NULL CHECK (score >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
