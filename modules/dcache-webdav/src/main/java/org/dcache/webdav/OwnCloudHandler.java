package org.dcache.webdav;

import org.eclipse.jetty.server.Request;
import org.eclipse.jetty.server.handler.AbstractHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * Created by bernardt on 23/06/14 for dcache-parent
 */
public class OwnCloudHandler extends AbstractHandler {

    private final Logger _log = LoggerFactory.getLogger(OwnCloudHandler.class);

    @Override
    public void handle(String target, Request baseRequest, HttpServletRequest request, HttpServletResponse response) throws IOException, ServletException {
        _log.info("ContextPathbase for handler {} is {}", this.getClass(), request.getContextPath());
    }
}
