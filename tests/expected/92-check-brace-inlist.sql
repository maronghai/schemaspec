
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `status` int NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
  `type` varchar(16) NOT NULL CHECK (type IN ('a', 'b', 'c')),
  `level` int NOT NULL CHECK (level IN (1, 2, 3, 4, 5))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
