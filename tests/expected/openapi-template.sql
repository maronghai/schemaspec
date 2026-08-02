
CREATE DATABASE `app` CHARACTER SET utf8mb4;

CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `orders` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `amount` decimal(16, 2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
