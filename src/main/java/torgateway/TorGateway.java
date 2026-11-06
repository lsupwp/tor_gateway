package torgateway;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.*;
import java.awt.geom.*;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Minimal Tor gateway GUI: one circular, glossy power button.
 * Red = direct connection, green = all traffic routed through Tor.
 * Privileged work is done by the shell scripts in ./scripts via pkexec.
 */
public final class TorGateway {

    private static final Path HOME = Path.of(
            System.getProperty("tor.gateway.home", System.getProperty("user.dir"))).toAbsolutePath();
    private static final Path RUNDIR = Path.of("/run/tor-gateway");
    private static final Path STATUS_FILE = RUNDIR.resolve("status");
    private static final Path PID_FILE = RUNDIR.resolve("tor.pid");

    private final JFrame frame = new JFrame("Tor Gateway");
    private final PowerButton button = new PowerButton();
    private final JLabel statusLabel = new JLabel("CLOSED", SwingConstants.CENTER);

    private boolean open;
    private boolean busy;
    private boolean hovered;
    private boolean pressed;
    private float glow = 0.45f;
    private float phase;

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new TorGateway().show());
    }

    private TorGateway() {
        frame.setDefaultCloseOperation(WindowConstants.DO_NOTHING_ON_CLOSE);
        frame.addWindowListener(new WindowAdapter() {
            @Override
            public void windowClosing(WindowEvent e) {
                onClose();
            }
        });

        JPanel root = new JPanel(new BorderLayout()) {
            @Override
            protected void paintComponent(Graphics g) {
                Graphics2D g2 = (Graphics2D) g.create();
                g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
                RadialGradientPaint bg = new RadialGradientPaint(
                        new Point2D.Float(getWidth() / 2f, getHeight() * 0.38f),
                        Math.max(getWidth(), getHeight()) * 0.85f,
                        new float[]{0f, 1f},
                        new Color[]{new Color(0x26, 0x26, 0x30), new Color(0x08, 0x08, 0x0A)});
                g2.setPaint(bg);
                g2.fillRect(0, 0, getWidth(), getHeight());
                g2.dispose();
            }
        };
        root.add(button);
        statusLabel.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 14));
        statusLabel.setForeground(new Color(0xE5, 0x3E, 0x3E));
        statusLabel.setBorder(new EmptyBorder(0, 0, 26, 0));
        root.add(statusLabel, BorderLayout.SOUTH);

        frame.setContentPane(root);
        frame.getContentPane().setBackground(new Color(0x08, 0x08, 0x0A));
        frame.setSize(430, 470);
        frame.setMinimumSize(new Dimension(340, 380));
        frame.setResizable(true);
        frame.setLocationRelativeTo(null);

        root.getInputMap(JComponent.WHEN_IN_FOCUSED_WINDOW)
                .put(KeyStroke.getKeyStroke("ESCAPE"), "close");
        root.getActionMap().put("close", new AbstractAction() {
            @Override
            public void actionPerformed(ActionEvent e) {
                onClose();
            }
        });

        new Timer(33, e -> tick()).start();
        new Timer(2000, e -> {
            if (!busy) {
                refresh();
            }
        }).start();
        refresh();
    }

    private void show() {
        frame.setVisible(true);
        if (!torInstalled()) {
            JOptionPane.showMessageDialog(frame,
                    "Tor is not installed.\n\nInstall it with:\nsudo apt install tor",
                    "Tor Gateway", JOptionPane.WARNING_MESSAGE);
        }
    }

    private void tick() {
        float target;
        if (busy) {
            target = 1.0f;
        } else if (open) {
            target = hovered ? 1.0f : 0.85f;
        } else {
            target = hovered ? 0.75f : 0.45f;
        }
        glow += (target - glow) * 0.12f;
        phase += busy ? 0.16f : 0.055f;
        button.repaint();
    }

    private boolean isOpen() {
        try {
            if (!Files.exists(STATUS_FILE)) {
                return false;
            }
            if (!Files.readString(STATUS_FILE).trim().equals("OPEN")) {
                return false;
            }
            long pid = Long.parseLong(Files.readString(PID_FILE).trim());
            return Files.readString(Path.of("/proc/" + pid + "/comm")).trim().equals("tor");
        } catch (Exception e) {
            return false;
        }
    }

    private boolean torInstalled() {
        return Files.isExecutable(Path.of("/usr/bin/tor")) || Files.isExecutable(Path.of("/usr/sbin/tor"));
    }

    private void refresh() {
        open = isOpen();
        statusLabel.setText(open ? "OPEN" : "CLOSED");
        statusLabel.setForeground(open ? new Color(0x30, 0xD1, 0x58) : new Color(0xE5, 0x3E, 0x3E));
        button.repaint();
    }

    private void toggle() {
        if (busy) {
            return;
        }
        runScript(open ? "tor-gateway-down.sh" : "tor-gateway-up.sh", null);
    }

    private void runScript(String script, Runnable afterSuccess) {
        busy = true;
        statusLabel.setText("WAITING");
        statusLabel.setForeground(new Color(0xF5, 0xA5, 0x24));
        button.repaint();
        final String[] lastLine = {""};

        new SwingWorker<Integer, Void>() {
            @Override
            protected Integer doInBackground() throws Exception {
                ProcessBuilder pb = new ProcessBuilder(
                        "pkexec", HOME.resolve("scripts").resolve(script).toString());
                pb.redirectErrorStream(true);
                Process process = pb.start();
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        if (!line.isBlank()) {
                            lastLine[0] = line;
                        }
                    }
                }
                return process.waitFor();
            }

            @Override
            protected void done() {
                int code = -1;
                try {
                    code = get();
                } catch (Exception ignored) {
                }
                busy = false;
                refresh();
                if (code != 0) {
                    String message = (code == 126 || code == 127)
                            ? "Authorization cancelled or pkexec unavailable."
                            : lastLine[0].isBlank()
                                    ? "Operation failed (exit code " + code + ")."
                                    : lastLine[0];
                    JOptionPane.showMessageDialog(frame, message,
                            "Tor Gateway", JOptionPane.ERROR_MESSAGE);
                } else if (afterSuccess != null) {
                    afterSuccess.run();
                }
            }
        }.execute();
    }

    private void onClose() {
        if (busy) {
            return;
        }
        if (!isOpen()) {
            frame.dispose();
            System.exit(0);
        }
        runScript("tor-gateway-down.sh", () -> {
            frame.dispose();
            System.exit(0);
        });
    }

    private Color accent() {
        if (busy) {
            return new Color(0xF5, 0xA5, 0x24);
        }
        return open ? new Color(0x30, 0xD1, 0x58) : new Color(0xE5, 0x3E, 0x3E);
    }

    private static Color mix(Color a, Color b, float t) {
        return new Color(
                Math.round(a.getRed() + (b.getRed() - a.getRed()) * t),
                Math.round(a.getGreen() + (b.getGreen() - a.getGreen()) * t),
                Math.round(a.getBlue() + (b.getBlue() - a.getBlue()) * t));
    }

    private final class PowerButton extends JComponent {

        private static final long serialVersionUID = 1L;

        PowerButton() {
            setPreferredSize(new Dimension(290, 290));
            setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
            setFocusable(true);
            addMouseListener(new MouseAdapter() {
                @Override
                public void mouseEntered(MouseEvent e) {
                    hovered = true;
                }

                @Override
                public void mouseExited(MouseEvent e) {
                    hovered = false;
                }

                @Override
                public void mousePressed(MouseEvent e) {
                    if (SwingUtilities.isLeftMouseButton(e)) {
                        pressed = true;
                        repaint();
                    }
                }

                @Override
                public void mouseReleased(MouseEvent e) {
                    if (pressed && SwingUtilities.isLeftMouseButton(e)) {
                        pressed = false;
                        repaint();
                        if (contains(e.getPoint())) {
                            toggle();
                        }
                    }
                }
            });
            addKeyListener(new KeyAdapter() {
                @Override
                public void keyPressed(KeyEvent e) {
                    if (e.getKeyCode() == KeyEvent.VK_SPACE || e.getKeyCode() == KeyEvent.VK_ENTER) {
                        toggle();
                    }
                }
            });
        }

        @Override
        protected void paintComponent(Graphics g) {
            Graphics2D g2 = (Graphics2D) g.create();
            g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            g2.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            g2.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);

            int w = getWidth();
            int h = getHeight();
            float cx = w / 2f;
            float cy = h / 2f;
            float r = Math.min(w, h) / 2f - 48f;

            Color accent = accent();
            float pulse = 0.88f + 0.12f * (float) Math.sin(phase);
            float intensity = Math.max(0f, Math.min(1f, glow)) * pulse;

            if (pressed) {
                g2.translate(cx, cy);
                g2.scale(0.975, 0.975);
                g2.translate(-cx, -cy);
            }

            // Soft shadow under the button.
            g2.setPaint(new RadialGradientPaint(
                    new Point2D.Float(cx, cy + r * 0.92f), r * 0.95f,
                    new float[]{0f, 1f},
                    new Color[]{new Color(0, 0, 0, 150), new Color(0, 0, 0, 0)}));
            g2.fill(new Ellipse2D.Float(cx - r * 1.05f, cy + r * 0.3f, r * 2.1f, r * 1.25f));

            // Outer glow rings.
            for (int i = 15; i >= 1; i--) {
                float gr = r + i * 2.6f;
                float t = (16 - i) / 15f;
                int alpha = (int) (110 * intensity * t * t);
                g2.setColor(new Color(accent.getRed(), accent.getGreen(), accent.getBlue(),
                        Math.min(255, alpha)));
                g2.fill(new Ellipse2D.Float(cx - gr, cy - gr, gr * 2, gr * 2));
            }

            // Button body.
            Color light = mix(accent, Color.WHITE, 0.42f);
            Color dark = mix(accent, Color.BLACK, 0.52f);
            g2.setPaint(new RadialGradientPaint(
                    new Point2D.Float(cx - r * 0.34f, cy - r * 0.40f), r * 1.75f,
                    new float[]{0f, 0.45f, 1f},
                    new Color[]{light, accent, dark}));
            Shape circle = new Ellipse2D.Float(cx - r, cy - r, r * 2, r * 2);
            g2.fill(circle);

            // Inner shading and gloss, clipped to the circle.
            Shape oldClip = g2.getClip();
            g2.clip(circle);

            g2.setPaint(new RadialGradientPaint(
                    new Point2D.Float(cx, cy + r * 0.10f), r * 1.28f,
                    new float[]{0f, 0.68f, 1f},
                    new Color[]{new Color(0, 0, 0, 0), new Color(0, 0, 0, 0), new Color(0, 0, 0, 150)}));
            g2.fill(circle);

            g2.setPaint(new LinearGradientPaint(
                    new Point2D.Float(0, cy - r), new Point2D.Float(0, cy + r * 0.08f),
                    new float[]{0f, 1f},
                    new Color[]{new Color(255, 255, 255, 165), new Color(255, 255, 255, 0)}));
            g2.fill(new Ellipse2D.Float(cx - r * 0.82f, cy - r * 0.98f, r * 1.64f, r * 1.06f));

            g2.setPaint(new RadialGradientPaint(
                    new Point2D.Float(cx - r * 0.30f, cy - r * 0.46f), r * 0.46f,
                    new float[]{0f, 1f},
                    new Color[]{new Color(255, 255, 255, 130), new Color(255, 255, 255, 0)}));
            g2.fill(new Ellipse2D.Float(cx - r * 0.76f, cy - r * 0.92f, r * 0.92f, r * 0.92f));

            g2.setClip(oldClip);

            // Rim light.
            g2.setStroke(new BasicStroke(r * 0.035f));
            g2.setPaint(new LinearGradientPaint(
                    new Point2D.Float(0, cy - r), new Point2D.Float(0, cy + r),
                    new float[]{0f, 0.5f, 1f},
                    new Color[]{new Color(255, 255, 255, 95),
                            new Color(255, 255, 255, 18),
                            new Color(0, 0, 0, 130)}));
            g2.draw(new Ellipse2D.Float(cx - r, cy - r, r * 2, r * 2));

            // Power glyph.
            float ir = r * 0.34f;
            g2.setStroke(new BasicStroke(r * 0.085f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
            g2.setColor(new Color(0, 0, 0, 60));
            g2.translate(0, r * 0.012f);
            g2.draw(new Arc2D.Float(cx - ir, cy - ir * 0.92f, ir * 2, ir * 2, 120, 300, Arc2D.OPEN));
            g2.draw(new Line2D.Float(cx, cy - r * 0.55f, cx, cy - r * 0.05f));
            g2.translate(0, -r * 0.012f);
            g2.setColor(new Color(255, 255, 255, 220));
            g2.draw(new Arc2D.Float(cx - ir, cy - ir * 0.92f, ir * 2, ir * 2, 120, 300, Arc2D.OPEN));
            g2.draw(new Line2D.Float(cx, cy - r * 0.55f, cx, cy - r * 0.05f));

            g2.dispose();
        }
    }
}
