package org.dcache.webdav;

import io.milton.http.Auth;
import io.milton.http.exceptions.NotAuthorizedException;
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

    /*
      ownCloud magic path
    */
    private static final String OC_PREFIX = "/remote.php/webdav";
    private static final String OC_STATUS = "status.php";

    @Override
    public void handle(String target, Request baseRequest, HttpServletRequest request, HttpServletResponse response) throws IOException, ServletException {
        _log.debug("ContextPath for handler {} is {}", this.getClass(), request.getContextPath());
        if (request.getContextPath().contains(OC_STATUS)) {
            OwnCloudResource ownCloudResource =  new OwnCloudResource();
            try {
                ownCloudResource.authorise((io.milton.http.Request) baseRequest, io.milton.http.Request.Method.CONNECT, new Auth("", new String("")) );
                ownCloudResource.sendContent(response.getOutputStream(), null, baseRequest.getParameterMap(), baseRequest.getContentType());
            } catch (NotAuthorizedException e) {
                _log.error("User not authorized to get ");
            }
            baseRequest.setHandled(true);
            response.getOutputStream().flush();
            response.flushBuffer();
        }
    }
}
