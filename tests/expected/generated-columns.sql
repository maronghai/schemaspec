
CREATE DATABASE `generated_columns` CHARACTER SET utf8mb4;

CREATE TABLE `products` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `price` int NOT NULL,
  `qty` int NOT NULL,
  `total` int NOT NULL GENERATED ALWAYS AS (price qty) VIRTUAL,
  `tax` int NOT NULL GENERATED ALWAYS AS (price 0.1) STORED
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
