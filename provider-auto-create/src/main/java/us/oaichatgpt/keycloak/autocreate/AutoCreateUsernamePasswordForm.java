package us.oaichatgpt.keycloak.autocreate;

import jakarta.ws.rs.core.MultivaluedMap;
import org.jboss.logging.Logger;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.authenticators.browser.UsernamePasswordForm;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.ModelDuplicateException;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserCredentialModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.utils.KeycloakModelUtils;
import org.keycloak.services.managers.AuthenticationManager;

public class AutoCreateUsernamePasswordForm extends UsernamePasswordForm {
    private static final Logger LOG = Logger.getLogger(AutoCreateUsernamePasswordForm.class);

    public AutoCreateUsernamePasswordForm(KeycloakSession session) {
        super(session);
    }

    @Override
    protected boolean validateForm(AuthenticationFlowContext context, MultivaluedMap<String, String> formData) {
        autoCreateUserIfNeeded(context, formData);
        return super.validateForm(context, formData);
    }

    private void autoCreateUserIfNeeded(AuthenticationFlowContext context, MultivaluedMap<String, String> formData) {
        String username = formData.getFirst(AuthenticationManager.FORM_USERNAME);
        if (username == null) {
            return;
        }

        String email = username.trim().toLowerCase();
        String[] domains = configuredDomains();
        String password = configuredPassword();

        if (domains.length == 0 || password.isBlank() || !isAllowedEmail(email, domains)) {
            return;
        }

        RealmModel realm = context.getRealm();
        KeycloakSession session = context.getSession();

        UserModel existingUser = KeycloakModelUtils.findUserByNameOrEmail(session, realm, email);
        if (existingUser != null) {
            return;
        }

        try {
            UserModel user = session.users().addUser(realm, email);
            String localPart = email.substring(0, email.indexOf('@'));

            user.setEmail(email);
            user.setEmailVerified(true);
            user.setEnabled(true);
            user.setFirstName(localPart);
            user.setLastName("User");
            user.credentialManager().updateCredential(UserCredentialModel.password(password));

            LOG.infof("Auto-created Keycloak user during login: realm=%s email=%s", realm.getName(), email);
        } catch (ModelDuplicateException duplicate) {
            LOG.debugf("User was created concurrently during login: realm=%s email=%s", realm.getName(), email);
        }
    }

    private boolean isAllowedEmail(String email, String[] domains) {
        for (String domain : domains) {
            if (email.endsWith("@" + domain)) {
                return true;
            }
        }
        return false;
    }

    private String[] configuredDomains() {
        String value = System.getenv("AUTO_CREATE_USER_DOMAINS");
        if (value == null || value.isBlank()) {
            value = System.getenv("AUTO_CREATE_USER_DOMAIN");
        }
        if (value == null || value.isBlank()) {
            return new String[0];
        }

        return java.util.Arrays.stream(value.split(","))
            .map(String::trim)
            .map(String::toLowerCase)
            .filter(domain -> !domain.isBlank())
            .distinct()
            .toArray(String[]::new);
    }

    private String configuredPassword() {
        String value = System.getenv("AUTO_CREATE_USER_PASSWORD");
        return value == null ? "" : value;
    }
}
