
CREATE TABLE "post" (
  "title" VARCHAR(255) NOT NULL
);

CREATE TABLE "comment" (
  "post_id" INTEGER NOT NULL CHECK (post_id = post.id),
  "body" VARCHAR(255) NOT NULL,
  INDEX "idx_post_id" ("post_id")
);
CREATE INDEX "idx_comment_post_id" ON "comment" ("post_id");
