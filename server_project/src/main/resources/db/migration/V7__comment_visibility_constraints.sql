-- Deletion cannot make an unreviewed or hidden comment public.
ALTER TABLE comment ADD COLUMN public_visibility INTEGER NOT NULL DEFAULT 0 CHECK(public_visibility IN (0,1));
UPDATE comment SET public_visibility=1 WHERE status='VISIBLE';
CREATE TRIGGER comment_parent_insert BEFORE INSERT ON comment
WHEN NEW.parent_id IS NOT NULL
BEGIN
  SELECT RAISE(ABORT,'invalid comment parent') WHERE NOT EXISTS (
    SELECT 1 FROM comment p WHERE p.id=NEW.parent_id AND p.story_id=NEW.story_id AND p.parent_id IS NULL
  );
END;
CREATE TRIGGER comment_parent_update BEFORE UPDATE OF parent_id,story_id ON comment
BEGIN
  SELECT RAISE(ABORT,'comment parent and story are immutable')
    WHERE NEW.parent_id IS NOT OLD.parent_id OR NEW.story_id<>OLD.story_id;
END;
