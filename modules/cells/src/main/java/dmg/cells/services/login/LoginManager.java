package dmg.cells.services.login;

import com.google.common.base.Splitter;
import com.google.common.collect.Iterables;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketAddress;
import java.net.SocketException;
import java.nio.channels.ServerSocketChannel;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;
import java.util.Map;
import java.util.StringTokenizer;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import dmg.cells.nucleus.CellAdapter;
import dmg.cells.nucleus.CellEvent;
import dmg.cells.nucleus.CellEventListener;
import dmg.cells.nucleus.CellMessage;
import dmg.cells.nucleus.CellNucleus;
import dmg.cells.nucleus.CellPath;
import dmg.cells.nucleus.CellVersion;
import dmg.cells.nucleus.NoRouteToCellException;
import dmg.util.Args;
import dmg.util.KeepAliveListener;
import dmg.util.StreamEngine;
import dmg.util.UserValidatable;

import org.dcache.auth.Subjects;
import org.dcache.util.Version;

import static com.google.common.base.Preconditions.checkArgument;
import static com.google.common.collect.Maps.newHashMap;

/**
 * *
 *
 * @author Patrick Fuhrmann
 * @version 0.1, 15 Feb 1998
 */
public class LoginManager
        extends CellAdapter
        implements UserValidatable
{
    private static final Object DEAD_CELL = new Object();

    private static final Logger LOGGER = LoggerFactory.getLogger(LoginManager.class);

    private static final Class<?>[] AUTH_CON_SIGNATURE =
            { CellNucleus.class, Args.class };

    private final CellNucleus _nucleus;
    private final Args _args;
    private final ListenThread _listenThread;
    private final String _locationManager;
    private final AtomicInteger _connectionDeniedCounter = new AtomicInteger();
    private final AtomicInteger _loginCounter = new AtomicInteger();
    private final AtomicInteger _loginFailures = new AtomicInteger();
    private final CellVersion _version;
    private final Constructor<?> _authConstructor;
    private final ExecutorService _executor;
    private final ScheduledExecutorService _scheduledExecutor;
    private final ConcurrentMap<String, Object> _children = new ConcurrentHashMap<>();
    private final CellPath _authenticator;
    private final KeepAliveThread _keepAlive;
    private final LoginBrokerHandler _loginBrokerHandler;
    private final String _protocol;
    private final Class<?> _authClass;
    private final LoginCellFactory _loginCellFactory;

    private volatile boolean _sending;
    private volatile int _maxLogin = -1;

    /**
     * <pre>
     *   usage   &lt;listenPort&gt; &lt;loginCellFactoryClass&gt;
     *           [-prot=ssh|telnet|raw]
     *                    default : telnet
     *           [-auth=&lt;authenticationClass&gt;]
     *                    default : ssh    : dmg.cells.services.login.SshSAuth_A
     *                              telnet : dmg.cells.services.login.TelnetSAuth_A
     *                              raw    : none
     *
     *         all residual arguments and all options are sent to
     *         the &lt;loginCellClass&gt; :
     *            &lt;init&gt;(String name , StreamEngine engine , Args args )
     *
     *         and to the Authentication module (class)
     *
     *            &lt;init&gt;(CellNucleus nucleus , Args args )
     *
     *         Both get their own copy.
     * </pre>
     */
    public LoginManager(String name, String argString) throws Exception
    {
        super(name, argString, false);

        _nucleus = getNucleus();
        _args = getArgs();
        try {
            if (_args.argc() < 2) {
                throw new
                        IllegalArgumentException(
                        "USAGE : ... <listenPort> <loginCell>" +
                                " [-prot=ssh|telnet|raw] [-auth=<authCell>]" +
                                " [-maxLogin=<n>|-1]" +
                                " [-keepAlive=<seconds>]" +
                                " [-acceptErrorWait=<msecs>]" +
                                " [args givenToLoginClass]");
            }

            _protocol = checkProtocol(_args.getOpt("prot"));
            LOGGER.info("Using protocol : {}", _protocol);

            int listenPort = Integer.parseInt(_args.argv(0));

            Args childArgs = new Args(argString.replaceFirst("(^|\\s)-export($|\\s)", ""));
            childArgs.shift();
            childArgs.shift();

            _loginCellFactory = new LoginCellFactoryBuilder()
                    .setName(_args.argv(1))
                    .setLoginManagerName(getCellName())
                    .setArgs(childArgs)
                    .build();
            _version = new CellVersion(Version.of(_loginCellFactory));

            // get the authentication
            _authenticator = new CellPath(_args.getOption("authenticator", "pam"));
            _authClass = toAuthClass(_args.getOpt("auth"), _protocol);
            Constructor<?> authConstructor;
            if (_authClass != null) {
                authConstructor = _authClass.getConstructor(AUTH_CON_SIGNATURE);
                LOGGER.trace("Using authentication constructor: {}", authConstructor);
            } else {
                authConstructor = null;
                LOGGER.trace("No authentication used");
            }
            _authConstructor = authConstructor;

            String maxLogin = _args.getOpt("maxLogin");
            if (maxLogin != null) {
                try {
                    _maxLogin = Integer.parseInt(maxLogin);
                } catch (NumberFormatException ee) {/* bad values ignored */}
            }

            _listenThread = new ListenThread(listenPort);
            LOGGER.info("Listening on port {}", _listenThread.getListenPort());

            _scheduledExecutor = Executors.newSingleThreadScheduledExecutor();

            String loginBroker = _args.getOpt("loginBroker");
            if (loginBroker != null) {
                Iterable<String> loginBrokers = Splitter.on(",").omitEmptyStrings().split(loginBroker);
                _loginBrokerHandler = new LoginBrokerHandler();
                _loginBrokerHandler.beforeSetup();
                _loginBrokerHandler.setExecutor(_scheduledExecutor);
                _loginBrokerHandler.setAddresses(_listenThread.getInetAddress());
                _loginBrokerHandler.setLoginBrokers(Iterables.toArray(loginBrokers, String.class));
                _loginBrokerHandler.setCellEndpoint(this);
                _loginBrokerHandler.setPort(_listenThread.getListenPort());
                _loginBrokerHandler.setProtocolEngine(_loginCellFactory.getName());
                _loginBrokerHandler.setProtocolFamily(_args.getOption("protocolFamily", _protocol));
                _loginBrokerHandler.setProtocolVersion(_args.getOption("protocolVersion", "1.0"));
                _loginBrokerHandler.setUpdateTime(_args.getLongOption("brokerUpdateTime"));
                _loginBrokerHandler.setUpdateTimeUnit(TimeUnit.valueOf(_args.getOption("brokerUpdateTimeUnit")));
                _loginBrokerHandler.setUpdateThreshold(_args.getDoubleOption("brokerUpdateOffset"));
                _loginBrokerHandler.afterSetup();
                _loginBrokerHandler.start();
                _loginBrokerHandler.afterStart();
                addCommandListener(_loginBrokerHandler);

                if (_maxLogin < 0) {
                    _maxLogin = 100000;
                }
            } else {
                _loginBrokerHandler = null;
            }

            if (_maxLogin < 0) {
                LOGGER.info("Maximum login feature disabled");
            } else {
                _nucleus.addCellEventListener(new LoginEventListener());
                LOGGER.info("Maximum logins set to: {}", _maxLogin);
            }

            // keep alive
            long keepAlive = TimeUnit.SECONDS.toMillis(_args.getLongOption("keepAlive", 0L));
            LOGGER.info("Keep alive set to {} ms", keepAlive);
            _keepAlive = new KeepAliveThread(keepAlive);

            // get the location manager
            _locationManager = _args.getOpt("lm");

            _executor = Executors.newCachedThreadPool(_nucleus);

            _nucleus.newThread(_listenThread, getCellName() + "-listen").start();
            _nucleus.newThread(new LocationThread(), getCellName() + "-location").start();
            _nucleus.newThread(_keepAlive, getCellName() + "-keepalive").start();
        } catch (IllegalArgumentException e) {
            start();
            kill();
            throw e;
        } catch (RuntimeException e) {
            LOGGER.warn("LoginManger >" + getCellName() + "< got exception : " + e, e);
            start();
            kill();
            throw e;
        } catch (Exception e) {
            start();
            kill();
            throw e;
        }

        start();
    }

    private static Class<?> toAuthClass(String authClassName, String protocol) throws ClassNotFoundException
    {
        Class<?> authClass = null;
        if (authClassName == null) {
            switch (protocol) {
            case "ssh":
                authClass = SshSAuth_A.class;
                break;
            case "raw":
                authClass = null;
                break;
            case "telnet":
                authClass = TelnetSAuth_A.class;
                break;
            }
        } else if (authClassName.equals("none")) {
//            _authClass = dmg.cells.services.login.NoneSAuth.class ;
        } else {
            authClass = Class.forName(authClassName);
        }
        if (authClass != null) {
            LOGGER.info("Using authentication Module: {}", authClass);
        }
        return authClass;
    }

    private static String checkProtocol(String protocol) throws IllegalArgumentException
    {
        if (protocol == null) {
            protocol = "telnet";
        }
        if (!(protocol.equals("ssh") ||
                protocol.equals("telnet") ||
                protocol.equals("raw"))) {
            throw new IllegalArgumentException("Protocol must be telnet or ssh or raw");
        }
        return protocol;
    }

    @Override
    public CellVersion getCellVersion()
    {
        return _version;
    }

    public static final String hh_get_children = "[-binary]";
    public Object ac_get_children(Args args)
    {
        boolean binary = args.hasOption("binary");
        if (binary) {
            String[] list = _children.keySet().toArray(new String[_children.size()]);
            return new LoginManagerChildrenInfo(getCellName(), getCellDomainName(), list);
        } else {
            StringBuilder sb = new StringBuilder();
            for (String child : _children.keySet()) {
                sb.append(child).append("\n");
            }
            return sb.toString();
        }
    }

    private class LoginEventListener implements CellEventListener
    {
        @Override
        public void cellCreated(CellEvent ce)
        {
        }

        @Override
        public void cellDied(CellEvent ce)
        {
            String removedCell = ce.getSource().toString();
            if (!removedCell.startsWith(getCellName())) {
                return;
            }

            /*  while in some cases remove may be issued prior cell is inserted into _children
       	     *  following trick is used:
       	     *  if there is no mapping for this cell, we create a 'dead' mapping, which will
       	     *  allow following put to identify it as a 'dead' and remove it.
       	     */
            Object cell = _children.putIfAbsent(removedCell, DEAD_CELL);
            if (cell != null) {
                _children.remove(removedCell, cell);
            }
            LOGGER.info("LoginEventListener : removing : {}", removedCell);
            loadChanged();
        }

        @Override
        public void cellExported(CellEvent ce)
        {
        }

        @Override
        public void routeAdded(CellEvent ce)
        {
        }

        @Override
        public void routeDeleted(CellEvent ce)
        {
        }
    }

    //
    // the 'send to location manager thread'
    //
    private class LocationThread implements Runnable
    {
        @Override
        public void run()
        {
            int listenPort = _listenThread.getListenPort();

            LOGGER.info("Sending 'listeningOn {} {}'", getCellName(), listenPort);
            _sending = true;
            String dest = _locationManager;
            if (dest == null) {
                return;
            }
            CellPath path = new CellPath(dest);
            CellMessage msg =
                    new CellMessage(
                            path,
                            "listening on " + getCellName() + " " + listenPort);

            for (int i = 0; !Thread.interrupted(); i++) {
                LOGGER.info("Sending ({}) 'listening on {} {}'", i, getCellName(), listenPort);

                try {
                    if (sendAndWait(msg, 5000) != null) {
                        LOGGER.info("Portnumber successfully sent to {}", dest);
                        _sending = false;
                        break;
                    }
                    LOGGER.warn("No reply from {}", dest);
                } catch (InterruptedException ie) {
                    LOGGER.warn("'send portnumber thread' interrupted");
                    break;
                } catch (Exception ee) {
                    LOGGER.warn("Problem sending portnumber {}", ee.toString());
                }
                try {
                    Thread.sleep(10000);
                } catch (InterruptedException ie) {
                    LOGGER.warn("'send portnumber thread' (sleep) interrupted");
                    break;
                }
            }
        }
    }

    private class KeepAliveThread implements Runnable
    {
        private long _keepAlive;

        private KeepAliveThread(long keepAlive)
        {
            _keepAlive = keepAlive;
        }

        @Override
        public synchronized void run()
        {
            LOGGER.info("KeepAlive Thread started");
            while (!Thread.interrupted()) {
                try {
                    if (_keepAlive < 1) {
                        wait();
                    } else {
                        wait(_keepAlive);
                    }
                } catch (InterruptedException ie) {
                    LOGGER.info("KeepAlive thread done (interrupted)");
                    break;
                }

                if (_keepAlive > 0) {
                    try {
                        runKeepAlive();
                    } catch (Throwable t) {
                        LOGGER.warn("runKeepAlive reported : {}", t.toString());
                    }
                }
            }
        }

        private synchronized void setKeepAlive(long keepAlive)
        {
            _keepAlive = keepAlive;
            LOGGER.info("Keep Alive value changed to {}", _keepAlive);
            notifyAll();
        }

        private long getKeepAlive()
        {
            return _keepAlive;
        }
    }

    public static final String hh_set_keepalive = "<keepAliveValue/seconds>";
    public String ac_set_keepalive_$_1(Args args)
    {
        long keepAlive = Long.parseLong(args.argv(0));
        _keepAlive.setKeepAlive(keepAlive * 1000L);
        return "keepAlive value set to " + keepAlive + " seconds";
    }

    public void runKeepAlive()
    {
        for (Object o : _children.values()) {
            if (o instanceof KeepAliveListener) {
                try {
                    ((KeepAliveListener) o).keepAlive();
                } catch (Throwable t) {
                    LOGGER.warn("Problem reported by : {} : {}", o, t);
                }
            }
        }
    }

    // the cell implementation
    @Override
    public String toString()
    {
        return "p=" + (_listenThread == null ? "???" : ("" + _listenThread.getListenPort())) +
                        ";c=" + _loginCellFactory.getName();
    }

    @Override
    public void getInfo(PrintWriter pw)
    {
        pw.println("  -- Login Manager $Revision: 1.46 $");
        pw.println("  Listen Port    : " + _listenThread.getListenPort());
        pw.println("  Protocol engine: " + _loginCellFactory.getName());
        pw.println("  Protocol       : " + _protocol);
        pw.println("  NioChannel     : " + (_listenThread._serverSocket.getChannel() != null));
        pw.println("  Auth Class     : " + _authClass);
        pw.println("  Logins created : " + _loginCounter);
        pw.println("  Logins failed  : " + _loginFailures);
        pw.println("  Logins denied  : " + _connectionDeniedCounter);
        pw.println("  KeepAlive      : " + (_keepAlive.getKeepAlive() / 1000L));

        if (_maxLogin > -1) {
            pw.println("  Logins/max     : " + _children.size() + "/" + _maxLogin);
        }

        if (_locationManager != null) {
            pw.println("  Location Mgr   : " + _locationManager +
                    " (" + (_sending ? "Sending" : "Informed") + ")");
        }

        if (_loginBrokerHandler != null) {
            pw.println("  LoginBroker Info :");
            _loginBrokerHandler.getInfo(pw);
        }
    }

    public static final String hh_set_max_logins = "<maxNumberOfLogins>|-1";
    public String ac_set_max_logins_$_1(Args args)
    {
        int n = Integer.parseInt(args.argv(0));
        checkArgument(n == -1 || _maxLogin >= 0, "Can't switch off maxLogin feature");
        checkArgument(n >= 0 || _maxLogin == -1, "Can't switch on maxLogin feature");
        _maxLogin = n;
        loadChanged();
        return "";
    }

    @Override
    public void cleanUp()
    {
        LOGGER.info("cleanUp requested by nucleus, closing listen socket");
        if (_listenThread != null) {
            _listenThread.shutdown();
        }
        if (_loginBrokerHandler != null) {
            _loginBrokerHandler.beforeStop();
            _loginBrokerHandler.stop();
        }
        if (_scheduledExecutor != null) {
            _scheduledExecutor.shutdown();
        }
        if (_executor != null) {
            _executor.shutdown();
        }
        if (_loginCellFactory != null) {
            _loginCellFactory.shutdown();
        }
        LOGGER.info("Bye Bye");
    }

    private class ListenThread implements Runnable
    {
        private int _listenPort;
        private ServerSocket _serverSocket;
        private boolean _shutdown;
        private Thread _this;
        private long _acceptErrorTimeout;
        private boolean _isDedicated;

        private ListenThread(int listenPort) throws Exception
        {
            _listenPort = listenPort;

            try {
                _acceptErrorTimeout = Long.parseLong(_args.getOpt("acceptErrorWait"));
            } catch (NumberFormatException ee) { /* bad values ignored */}

            openPort();
        }

        private void startLoginBrokerUpdates()
        {
            if (_loginBrokerHandler != null) {
                _loginBrokerHandler.start();
            }
        }

        private void stopLoginBrokerUpdates()
        {
            if (_loginBrokerHandler != null) {
                _loginBrokerHandler.stop();
            }
        }

        private void openPort() throws Exception
        {
            String ssf = _args.getOpt("socketfactory");
            String local = _args.getOpt("listen");

            if (ssf == null) {
                SocketAddress socketAddress;

                if (local == null || local.equals("any")) {
                    socketAddress = new InetSocketAddress(_listenPort);
                } else {
                    socketAddress = new InetSocketAddress(InetAddress.getByName(local), _listenPort);
                    _isDedicated = true;
                }

                _serverSocket = ServerSocketChannel.open().socket();
                _serverSocket.bind(socketAddress);
                _listenPort = _serverSocket.getLocalPort();

            } else {
                StringTokenizer st = new StringTokenizer(ssf, ",");

                /*
                 * socket factory initialization has following format:
                 *   <classname>[<arg1>,...]
                 */
                checkArgument(st.countTokens() >= 2, "Invalid Arguments for 'socketfactory'");

                String tunnelFactoryClass = st.nextToken();
                /*
                 * the rest is passed to factory constructor as String[]
                 */
                String[] farctoryArgs = new String[st.countTokens()];
                for (int i = 0; st.hasMoreTokens(); i++) {
                    farctoryArgs[i] = st.nextToken();
                }


                Class<?>[] constructorArgClassA = {String[].class, Map.class};
                Class<?>[] constructorArgClassB = {String[].class};

                Class<?> ssfClass = Class.forName(tunnelFactoryClass);
                Object[] args;

                Constructor<?> ssfConstructor;
                try {
                    ssfConstructor = ssfClass.getConstructor(constructorArgClassA);
                    args = new Object[2];
                    args[0] = farctoryArgs;
                    Map<String, Object> map = newHashMap(getDomainContext());
                    map.put("UserValidatable", LoginManager.this);
                    args[1] = map;
                } catch (Exception ee) {
                    ssfConstructor = ssfClass.getConstructor(constructorArgClassB);
                    args = new Object[1];
                    args[0] = farctoryArgs;
                }

                Object obj;
                try {
                    obj = ssfConstructor.newInstance(args);
                } catch (InvocationTargetException e) {
                    Throwable t = e.getCause();
                    if (t instanceof Exception) {
                        throw (Exception) t;
                    } else {
                        throw new Exception(t.getMessage(), t);
                    }
                }

                Method meth = ssfClass.getMethod("createServerSocket", new Class[0]);
                _serverSocket = (ServerSocket) meth.invoke(obj);

                if (local == null || local.equals("any")) {
                    _serverSocket.bind(new InetSocketAddress(_listenPort));
                } else {
                    _serverSocket.bind(new InetSocketAddress(InetAddress.getByName(local), _listenPort));
                    _isDedicated = true;
                }

                LOGGER.info("ListenThread : got serverSocket class : {}", _serverSocket.getClass().getName());
            }

            LOGGER.debug("Socket BIND local = {}", _serverSocket.getLocalSocketAddress());
            LOGGER.info("Nio Socket Channel : {}", (_serverSocket.getChannel() != null));
        }

        public int getListenPort()
        {
            return _listenPort;
        }

        public List<InetAddress> getInetAddress()
        {
            if (!_isDedicated) {
                // put all local Ip addresses, except loopback
                List<InetAddress> addresses = new ArrayList<>();
                try {
                    Enumeration<NetworkInterface> ifList = NetworkInterface.getNetworkInterfaces();
                    while (ifList.hasMoreElements()) {
                        NetworkInterface ne = ifList.nextElement();
                        Enumeration<InetAddress> ipList = ne.getInetAddresses();
                        while (ipList.hasMoreElements()) {
                            InetAddress ia = ipList.nextElement();
                            // Currently we do not handle ipv6
                            if (!(ia instanceof Inet4Address)) {
                                continue;
                            }
                            if (!ia.isLoopbackAddress()) {
                                addresses.add(ia);
                            }
                        }
                    }
                } catch (SocketException ignored) {
                }
                return addresses;
            } else if (_serverSocket != null) {
                return Collections.singletonList(_serverSocket.getInetAddress());
            } else {
                return Collections.emptyList();
            }
        }

        @Override
        public void run()
        {
            _this = Thread.currentThread();

            try {
                startLoginBrokerUpdates();
                while (true) {
                    Socket socket;
                    try {
                        socket = _serverSocket.accept();
                        socket.setKeepAlive(true);
                        socket.setTcpNoDelay(true);
                        LOGGER.debug("Socket OPEN (ACCEPT) remote = {} local = {}",
                                socket.getRemoteSocketAddress(), socket.getLocalSocketAddress());
                        LOGGER.info("Nio Channel (accept) : {}", (socket.getChannel() != null));

                        int currentChildCount = _children.size();
                        LOGGER.info("New connection : {}", currentChildCount);
                        if ((_maxLogin > -1) && (currentChildCount >= _maxLogin)) {
                            _connectionDeniedCounter.incrementAndGet();
                            LOGGER.warn("Connection denied: Number of allowed logins exceeded ({} > {}).", currentChildCount, _maxLogin);
                            ShutdownEngine engine = new ShutdownEngine(socket);
                            engine.start();
                            continue;
                        }
                        LOGGER.info("Connection request from {}", socket.getInetAddress());
                        _executor.execute(new RunEngineThread(socket));
                    } catch (InterruptedIOException ioe) {
                        LOGGER.warn("Listen thread interrupted");
                        try {
                            _serverSocket.close();
                        } catch (IOException e) {
                            ioe.addSuppressed(e);
                        }
                        break;
                    } catch (IOException ioe) {
                        if (_serverSocket.isClosed()) {
                            break;
                        }

                        LOGGER.warn("Got an IO Exception ( closing server ) : {}", ioe.toString());
                        try {
                            _serverSocket.close();
                        } catch (IOException e) {
                            ioe.addSuppressed(e);
                        }
                        if (_acceptErrorTimeout <= 0L) {
                            break;
                        }
                        LOGGER.warn("Waiting {} msecs", +_acceptErrorTimeout);
                        try {
                            Thread.sleep(_acceptErrorTimeout);
                        } catch (InterruptedException ee) {
                            LOGGER.warn("Recovery halt interrupted");
                            break;
                        }
                        LOGGER.warn("Resuming listener");
                        try {

                            openPort();

                        } catch (Exception ee) {
                            LOGGER.warn("openPort reported : {}", ee.toString());
                            LOGGER.warn("Waiting {} msecs", _acceptErrorTimeout);
                            try {
                                Thread.sleep(_acceptErrorTimeout);
                            } catch (InterruptedException eee) {
                                LOGGER.warn("Recovery halt interrupted");
                                break;
                            }
                        }
                    }

                }
            } finally {
                stopLoginBrokerUpdates();
            }
            LOGGER.info("Listen thread finished");
        }


        /**
         * Class that closes the output half of a TCP socket, drains any pending input and closes the input once drained.
         * After creation, the {@link #start} method must be called.  The activity occurs on a separate thread, allowing
         * the start method to be non-blocking.
         */
        public class ShutdownEngine extends Thread
        {
            private final Socket _socket;

            public ShutdownEngine(Socket socket)
            {
                super("Shutdown");
                _socket = socket;
            }

            @Override
            public void run()
            {
                InputStream inputStream;
                OutputStream outputStream;
                try {
                    inputStream = _socket.getInputStream();
                    outputStream = _socket.getOutputStream();
                    outputStream.close();
                    byte[] buffer = new byte[1024];
                    /*
                     * eat the outstanding date from socket and close it
                     */
                    while (inputStream.read(buffer, 0, buffer.length) > 0) {
                    }
                    inputStream.close();
                } catch (IOException ee) {
                    LOGGER.warn("Shutdown : {}", ee.getMessage());
                } finally {
                    try {
                        LOGGER.debug("Socket CLOSE (ACCEPT) remote = {} local = {}",
                                _socket.getRemoteSocketAddress(), _socket.getLocalSocketAddress());
                        _socket.close();
                    } catch (IOException e) {
                        // ignore
                    }
                }

                LOGGER.info("Shutdown : done");
            }
        }

        public synchronized void shutdown()
        {
            LOGGER.info("Listen thread shutdown requested");
            //
            // it is still hard to stop an Pending I/O call.
            //
            if (_shutdown || (_serverSocket == null)) {
                return;
            }
            _shutdown = true;

            try {
                LOGGER.debug("Socket SHUTDOWN local = {}", _serverSocket.getLocalSocketAddress());
                _serverSocket.close();
            } catch (IOException ee) {
                LOGGER.warn("ServerSocket close: {}", ee.toString());
            }

            if (_serverSocket.getChannel() == null) {
                LOGGER.info("Using faked connect to shutdown listen port");
                try {
                    new Socket("localhost", _listenPort).close();
                } catch (IOException e) {
                    LOGGER.debug("ServerSocket faked connect: {}", e.getMessage());
                }
            }

            _this.interrupt();

            LOGGER.info("Shutdown sequence done");
        }
    }

    private class RunEngineThread implements Runnable
    {
        private Socket _socket;

        private RunEngineThread(Socket socket)
        {
            _socket = socket;
        }

        @Override
        public void run()
        {
            Thread t = Thread.currentThread();
            try {
                LOGGER.info("acceptThread ({}): creating protocol engine", t);

                StreamEngine engine;
                if (_authConstructor != null) {
                    engine = StreamEngineFactory.newStreamEngine(_socket, _protocol,
                            _nucleus, getArgs());
                } else {
                    engine = StreamEngineFactory.newStreamEngineWithoutAuth(_socket,
                            _protocol);
                }

                String userName = Subjects.getDisplayName(engine.getSubject());
                LOGGER.info("acceptThread ({}): connection created for user {}", t, userName);
                Object[] args;

                int p = userName.indexOf('@');

                if (p > -1) {
                    userName = p == 0 ? "unknown" : userName.substring(0, p);
                }

                Object cell = _loginCellFactory.newCell(engine, userName);
                if (_maxLogin > -1) {
                    try {
                        Method m = cell.getClass().getMethod("getCellName");
                        String cellName = (String) m.invoke(cell);
                        LOGGER.info("Invoked cell name : {}", cellName);
                        if (_children.putIfAbsent(cellName, cell) == DEAD_CELL) {
                            /*  while cell may be already gone do following trick:
                             *  if put return an old cell, then it's a dead cell and we
                             *  have to remove it. Dead cell is inserted by cleanup procedure:
                             *  if a remove for non existing cells issued, then cells is dead, and
                             *  we put it into _children.
                             */
                            _children.remove(cellName, DEAD_CELL);
                        }
                        loadChanged();
                    } catch (IllegalAccessException | IllegalArgumentException | NoSuchMethodException | SecurityException | InvocationTargetException ee) {
                        LOGGER.warn("Can't determine child name", ee);
                    }
                }
                _loginCounter.incrementAndGet();

            } catch (InvocationTargetException e) {
                Throwable cause = e.getCause();
                if (cause instanceof Error) {
                    throw (Error) cause;
                }
                LOGGER.warn("Exception (ITE) in secure protocol : {}", cause);
                try {
                    _socket.close();
                } catch (IOException ee) {/* dead any way....*/}
                _loginFailures.incrementAndGet();
            } catch (Exception e) {
                LOGGER.warn("Exception in secure protocol : {}", e.toString());
                try {
                    _socket.close();
                } catch (IOException ee) {/* dead any way....*/}
                _loginFailures.incrementAndGet();
            }
        }
    }

    private void loadChanged()
    {
        int children = _children.size();
        LOGGER.info("New child count : {}", children);
        if (_loginBrokerHandler != null) {
            _loginBrokerHandler.setLoad(children, _maxLogin);
        }
    }

    @Override
    public boolean validateUser(String userName, String password)
    {
        String[] request = { "request", userName, "check-password", userName, password };

        try {
            CellMessage msg = new CellMessage(_authenticator, request);
            msg = sendAndWait(msg, 10000);
            if (msg == null) {
                LOGGER.warn("Pam request timed out {}", Thread.currentThread().getStackTrace());
                return false;
            }

            Object[] r = (Object[]) msg.getMessageObject();

            return (Boolean) r[5];

        } catch (NoRouteToCellException e) {
            LOGGER.warn(e.getMessage());
            return false;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }
}
