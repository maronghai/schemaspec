
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `role` ENUM('admin', 'user', 'guest') NOT NULL,
  `status` ENUM('A', 'B', 'C') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
