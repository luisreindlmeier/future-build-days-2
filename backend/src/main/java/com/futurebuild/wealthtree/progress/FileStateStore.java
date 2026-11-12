package com.futurebuild.wealthtree.progress;

import java.io.IOException;
import java.io.InputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/** One file on disk (Java serialization). Good enough for a hackathon; swap for a database later. */
public class FileStateStore implements StateStore {
    private final Path file;

    public FileStateStore(Path file) { this.file = file; }

    @Override
    public synchronized State load() {
        if (!Files.exists(file)) return null;
        try (InputStream in = Files.newInputStream(file); ObjectInputStream o = new ObjectInputStream(in)) {
            return (State) o.readObject();
        } catch (IOException | ClassNotFoundException | ClassCastException e) {
            System.err.println("wealth-tree: could not read " + file + " (" + e + "); starting from demo data");
            return null;
        }
    }

    @Override
    public synchronized void save(State s) {
        try {
            if (file.getParent() != null) Files.createDirectories(file.getParent());
            Path tmp = file.resolveSibling(file.getFileName() + ".tmp");
            try (OutputStream out = Files.newOutputStream(tmp); ObjectOutputStream o = new ObjectOutputStream(out)) {
                o.writeObject(s);
            }
            Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            throw new IllegalStateException("Could not save progress to " + file, e);
        }
    }

    @Override
    public synchronized void clear() {
        try { Files.deleteIfExists(file); } catch (IOException e) { throw new IllegalStateException(e); }
    }
}
