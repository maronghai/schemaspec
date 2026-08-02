
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `gender` ENUM('M', 'F', 'X') NOT NULL,
  `status` ENUM('pending', 'active', 'closed') NOT NULL DEFAULT 'pending',
  `role` ENUM('admin', 'user', 'guest') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
