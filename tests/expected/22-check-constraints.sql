
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `constrained` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `age` int NOT NULL CHECK (age BETWEEN 0 AND 150),
  `score` decimal(16, 2) NOT NULL CHECK (score BETWEEN 0 AND 100),
  `amount` decimal(16, 2) NOT NULL CHECK (amount > 0),
  `qty` int NOT NULL CHECK (qty >= 1),
  `type` varchar(16) NOT NULL CHECK (type IN ('a', 'b', 'c')),
  `range2` int NOT NULL CHECK (range2 >= 0 AND range2 <= 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
