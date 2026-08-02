
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL,
  `role` ENUM('admin', 'user', 'guest') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
