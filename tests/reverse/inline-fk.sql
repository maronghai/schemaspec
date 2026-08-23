CREATE TABLE users (
  id INT PRIMARY KEY
);

CREATE TABLE posts (
  id INT PRIMARY KEY,
  author_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  editor_id INT REFERENCES users,
  tag_a INT REFERENCES tags(a, b)
);
