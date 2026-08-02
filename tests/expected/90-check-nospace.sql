
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `constrained` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `age` int NOT NULL CHECK (age BETWEEN 0 AND 150),
  `amount` decimal(16, 2) NOT NULL CHECK (amount > 0),
  `ratio` decimal(20, 6) NOT NULL CHECK (ratio >= 0 AND ratio <= 100),
  `type` varchar(16) NOT NULL CHECK (type IN ('a', 'b', 'c'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
