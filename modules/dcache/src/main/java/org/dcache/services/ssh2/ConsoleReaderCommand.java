package org.dcache.services.ssh2;

import com.google.common.base.Charsets;
import dmg.cells.applets.login.DomainObjectFrame;
import jline.ANSIBuffer;
import jline.ConsoleReader;
import jline.History;
import jline.UnixTerminal;
import org.apache.sshd.server.Command;
import org.apache.sshd.server.Environment;
import org.apache.sshd.server.ExitCallback;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.sql.Timestamp;
import java.util.Calendar;
import java.util.Date;

import diskCacheV111.admin.UserAdminShell;

import dmg.cells.nucleus.CellEndpoint;
import dmg.cells.nucleus.NoRouteToCellException;
import dmg.cells.nucleus.SerializationException;
import dmg.util.CommandException;
import dmg.util.CommandExitException;
import dmg.util.CommandPanicException;
import dmg.util.CommandSyntaxException;
import dmg.util.CommandThrowableException;
import dmg.util.RequestTimeOutException;
import dmg.util.command.HelpFormat;

/**
 * This class implements the Command Interface, which is part of the sshd-core
 * library allowing to access input and output stream of the ssh2Server. This
 * class is also the point of connecting the ssh2 streams to the
 * userAdminShell's input and output streams. The run() method of the thread
 * takes care of handling the user input. It lets the userAdminShell execute the
 * commands entered by the user, waits for the answer and outputs the answer to
 * the terminal of the user.
 * @author bernardt
 */

public class ConsoleReaderCommand implements Command, Runnable {

    private final static Logger _logger =
        LoggerFactory.getLogger(ConsoleReaderCommand.class);
    private static final int HISTORY_SIZE = 50;
    private static final String NL = "\r\n";
    private static final String CONTROL_C_ANSWER =
        "Got interrupt. Please issue \'logoff\' from "
        + "within the Admin Cell to end this session.\n";
    private static File _historyFile;
    private static final Class<?>[][] COM_SIGNATURE = {
            { Object.class },
            { String.class },
            { String.class, Object.class  },
            { String.class, String.class  }
    };
    private Method[] _commandMethod = new Method[COM_SIGNATURE.length];

    private Object _commandObject;
    private UserAdminShell _userAdminShell;
    private InputStream _in;
    private ExitCallback _exitCallback;
    private OutputStream _out;
    private OutputStreamWriter _outWriter;
    private Thread _adminShellThread;
    private Thread _binaryThread;
    private ConsoleReader _console;
    private History _history;
    private boolean _useColors;
    private final CellEndpoint _endpoint;

    public ConsoleReaderCommand(CellEndpoint endpoint,
            File historyFile, boolean useColor) {
        _useColors = useColor;
        _endpoint = endpoint;
        if (historyFile != null && historyFile.isFile()) {
            try {
                _history = new History(historyFile);
                _history.setMaxSize(HISTORY_SIZE);
            } catch (IOException e) {
                _logger.warn("History creation failed: " + e.getMessage());
            }
        }
    }

    @Override
    public void destroy() {
        if (_adminShellThread != null) {
            _adminShellThread.interrupt();
        }
    }

    @Override
    public void setErrorStream(OutputStream err) {
        // we don't use the error stream
    }

    @Override
    public void setExitCallback(ExitCallback callback) {
        _exitCallback = callback;
    }

    @Override
    public void setInputStream(InputStream in) {
        _in = in;
    }

    public InputStream getInputStream() {
        return _in;
    }

    @Override
    public void setOutputStream(OutputStream out) {
        _out = out;
        _logger.debug("OutputStream is: {}", _out);
        _outWriter = new SshOutputStreamWriter(out);
    }

    public OutputStream getOutputStream() {
        return _out;
    }

    @Override
    public void start(Environment env) throws IOException {
        String user = env.getEnv().get(Environment.ENV_USER);
        _userAdminShell = new UserAdminShell(user, _endpoint,
                _endpoint.getArgs());
        _console = new ConsoleReader(_in, _outWriter, null, new ConsoleReaderTerminal(env));
        _adminShellThread = new Thread(this);
        _adminShellThread.start();
    }

    @Override
    public void run() {
        try {
            initAdminShell();
            runAsciiMode();
        } catch (IOException e) {
            _logger.warn(e.getMessage());
        } finally {
            try {
                cleanUp();
            } catch (IOException e) {
                _logger.warn("Failed to shutdown console cleanly: "
                        + e.getMessage());
            }
            _exitCallback.onExit(0);
        }
    }

    private void initAdminShell() throws IOException {
        if (_history != null) {
            _console.setHistory(_history);
            _console.setUseHistory(true);
            _logger.debug("History enabled.");
        }

        String hello = "";
        if (_userAdminShell != null) {
            _console.addCompletor(_userAdminShell);
            hello = _userAdminShell.getHello();
        }

        _console.addTriggeredAction(ConsoleReader.CTRL_C, new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent event) {
                try {
                    _console.printString(CONTROL_C_ANSWER);
                    _console.printString(NL);
                    _console.printString("\r");
                    _console.flushConsole();
                } catch (IOException e) {
                    _logger.warn("I/O failure for Ctrl-C: " + e);
                }
            }
        });

        _console.printString(hello);
        _console.printString(NL);
        _console.flushConsole();
    }

    private void runAsciiMode() throws IOException {
        while (!_adminShellThread.isInterrupted()) {
            String prompt = new ANSIBuffer().green(_userAdminShell.getPrompt()).toString(_useColors);
            String str = _console.readLine(prompt);
            Object result;

            if (str.equals("$BINARY$")) {
                _logger.debug("Received Binary");
                _console.printString(str);
                _console.printNewline();
                _console.flushConsole();
                try {
                    runBinaryMode();
                } catch (ClassNotFoundException e) {
                    e.printStackTrace();  //To change body of catch statement use File | Settings | File Templates.
                }
                break;
            }

            try {
                if (str == null) {
                    throw new CommandExitException();
                }
                if (_useColors) {
                    String trimmed = str.trim();
                    if (trimmed.startsWith("help ")) {
                        str = "help -format=" + HelpFormat.ANSI + trimmed.substring(4);
                    } else if (trimmed.equals("help")) {
                        str = "help -format=" + HelpFormat.ANSI;
                    }
                }
                result = _userAdminShell.executeCommand(str);
            } catch (CommandSyntaxException e) {
                result = e.getMessage()
                + " Please enter \'help\' to see all commands that can be used.";
            } catch (IllegalArgumentException e) {
                result = e.getMessage()
                + " (Please check the spelling of your command or your config file(s)!)";
            } catch (CommandExitException e) {
                break;
            } catch (SerializationException e) {
                result =
                    "There is a bug here, please report to support@dcache.org";
                _logger.error("This must be a bug, please report to "
                        + "support@dcache.org: {}" + e.getMessage());
            } catch (CommandException e) {
                if (e instanceof CommandPanicException) {
                    _logger.warn("Something went wrong during the remote "
                            + "execution of the command: {}"
                            + ((CommandPanicException) e).getTargetException());
                    return;
                }
                if (e instanceof CommandThrowableException) {
                    _logger.warn("Something went wrong during the remote "
                            + "execution of the command: {}"
                            + ((CommandThrowableException) e)
                            .getTargetException());
                    return;
                }
                result =
                    "There is a bug here, please report to support@dcache.org: "
                    + e.getMessage();
                _logger.warn("Unexpected exception, please report this "
                        + "bug to support@dcache.org");
            } catch (NoRouteToCellException e) {
                result =
                    "Cell name does not exist or cell is not started: "
                    + e.getMessage();
                _logger.warn("The cell the command was sent to is no "
                        + "longer there: {}", e.getMessage());
            } catch (InterruptedException e) {
                result = e.getMessage();
            } catch (RequestTimeOutException e) {
                result = e.getMessage();
                _logger.warn(e.getMessage());
            } catch (RuntimeException e) {
                result = String.format("Command '%s' triggered bug; please" +
                        " located this message in log file and send an email" +
                        " to support@dcache.org with this line and the" +
                        " following stack-trace", str);
                _logger.warn((String)result, e);
            } catch (Exception e) {
                result = e.getMessage();
                if(result == null) {
                    result = e.getClass().getSimpleName() + ": (null)";
                }
            }

            if (result != null) {
                String s;
                if (result instanceof CommandSyntaxException) {
                    CommandSyntaxException e = (CommandSyntaxException) result;
                    ANSIBuffer sb = new ANSIBuffer();
                    sb.red("Syntax error: " + e.getMessage() + "\n");
                    String help = e.getHelpText();
                    if (help != null) {
                        sb.cyan("Help : \n");
                        sb.cyan(help);
                    }
                    s = sb.toString(_useColors);
                } else {
                    s = result.toString();
                }

                if (!s.isEmpty()) {
                    _console.printString(s);
                    _console.printNewline();
                }
            }
        }
    }

    private void runBinaryMode()
            throws IOException, ClassNotFoundException
    {
        _logger.debug("Switched to binary mode.");
        ObjectOutputStream out =
                new ObjectOutputStream(this.getOutputStream());
        _logger.debug("ObjectOutputStream created");
        out.flush();
        Calendar calendar = Calendar.getInstance();
        Date currentTimestamp = new Timestamp(calendar.getTime().getTime());
        _logger.debug("{} flushed ObjectOutputStream", currentTimestamp);
        ObjectInputStream in =
                new ObjectInputStream(this.getInputStream());
        _logger.debug("ObjectInputStream created");
        Object obj;
        while ((obj = in.readObject()) != null) {
            _logger.debug("Reading objects from stream.");
            if (obj instanceof DomainObjectFrame) {
                _logger.debug("Object is DomainObjectFrame");
                new BinaryExec(out, (DomainObjectFrame) obj, Thread.currentThread());
            } else {
                _logger.error("Won't accept non DomainObjectFrame : " + obj.getClass());
            }
        }
    }

    private void cleanUp() throws IOException {
        if (_history != null) {
            PrintWriter out = _history.getOutput();
            if (out != null) {
                out.close();
            }
        }
        _console.printString(NL);
        _console.flushConsole();
        _outWriter.close();
    }

    private static class ConsoleReaderTerminal extends UnixTerminal {

        private final static int DEFAULT_WIDTH = 80;
        private final static int DEFAULT_HEIGHT = 24;
        private final Environment _env;

        private ConsoleReaderTerminal(Environment env) {
            _env = env;
        }

        @Override
        public void initializeTerminal()
            throws IOException, InterruptedException
        {
            /* UnixTerminal expects a tty to have been allocated. That
             * is not the case for StreamObjectCell and hence we skip
             * the usual initialization.
             */
        }

        @Override
        public int readCharacter(InputStream in) throws IOException
        {
            int c = super.readCharacter(in);
            if (c == DELETE) {
                c = BACKSPACE;
            }
            return c;
        }

        @Override
        public int getTerminalHeight() {
            String h = _env.getEnv().get(Environment.ENV_LINES);
            if(h != null) {
                try {
                    return Integer.parseInt(h);
                }catch(NumberFormatException e) {
                    // nop
                }
            }
            return DEFAULT_HEIGHT;
        }

        @Override
        public int getTerminalWidth() {
            String h = _env.getEnv().get(Environment.ENV_COLUMNS);
            if(h != null) {
                try {
                    return Integer.parseInt(h);
                }catch(NumberFormatException e) {
                    // nop
                }
            }
            return DEFAULT_WIDTH;
        }
    }

    private static class SshOutputStreamWriter extends OutputStreamWriter {

        public SshOutputStreamWriter(OutputStream out) {
            super(out, Charsets.UTF_8);
        }

        @Override
        public void write(char[] c) throws IOException {
            write(c, 0, c.length);
        }

        @Override
        public void write(char[] c, int off, int len) throws IOException {
            for (int i = off; i < (off + len); i++) {
                write((int) c[i]);
            }
        }

        @Override
        public void write(int c) throws IOException {
            if (c == '\n') {
                super.write(0xa);
                super.write(0xd);
            } else {
                super.write(c);
            }
        }

        @Override
        public void write(String str) throws IOException {
            for (int i = 0; i < str.length(); i++) {
                write(str.charAt(i));
            }
        }

        @Override
        public void write(String str, int off, int len) throws IOException {
            for (int i = off; i < (off + len); i++) {
                write(str.charAt(i));
            }
        }
    }

    private class BinaryExec implements Runnable
    {
        private final ObjectOutputStream _out;
        private final DomainObjectFrame _frame;
        private final Thread _parent;

        BinaryExec(ObjectOutputStream out,
                   DomainObjectFrame frame, Thread parent)
        {
            _out = out;
            _frame  = frame;
            _parent = parent;
            _binaryThread = new Thread(this);
            _binaryThread.start();
        }

        @Override
        public void run()
        {
            _logger.debug("Run binary thread.");
            Object result;
            boolean done = false;
            _logger.debug("Frame id " + _frame.getId() + " arrived");
            try {
                if (_frame.getDestination() == null) {
                    Object [] array  = new Object[1];
                    array[0] = _frame.getPayload();
                    if (_commandMethod[0] != null) {
                        _logger.debug("Choosing executeCommand(Object)");
                        result = _commandMethod[0].invoke(_commandObject, array);
                    } else if(_commandMethod[1] != null) {
                        _logger.debug("Choosing executeCommand(String)");
                        array[0] = array[0].toString();
                        result = _commandMethod[1].invoke(_commandObject, array);

                    } else {
                        throw new
                                Exception("PANIC : not found : executeCommand(String or Object)");
                    }
                } else {
                    Object [] array  = new Object[2];
                    array[0] = _frame.getDestination();
                    array[1] = _frame.getPayload();
                    if (_commandMethod[2] != null) {
                        _logger.debug("Choosing executeCommand(String destination, Object)");
                        result = _commandMethod[2].invoke(_commandObject, array);

                    } else if (_commandMethod[3] != null) {
                        _logger.debug("Choosing executeCommand(String destination, String)");
                        array[1] = array[1].toString();
                        result = _commandMethod[3].invoke(_commandObject, array);
                    } else {
                        throw new
                                Exception("PANIC : not found : "+
                                "executeCommand(String/String or Object/String)");
                    }
                }
            } catch (InvocationTargetException ite) {
                result = ite.getTargetException();
                done = result instanceof CommandExitException;
            } catch (Exception ae) {
                result = ae;
            }
            _frame.setPayload(result);
            try {
                synchronized(_out){
                    _out.writeObject(_frame);
                    _out.flush();
                    _out.reset();  // prevents memory leaks...
                }
            } catch (IOException e) {
                _logger.error("Problem sending result : " + e);
            }
            if (done) {
                _parent.interrupt();
            }
        }
    }
}
