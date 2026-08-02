
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `status_check` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `status` varchar(16) NOT NULL CHECK (status IN ('active', 'inactive', 'pending')),
  `priority` int NOT NULL CHECK (priority IN (1, 2, 3, 4, 5))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
