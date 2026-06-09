package us.oaichatgpt.keycloak.autocreate;

import java.util.Collections;
import java.util.List;
import java.util.Set;
import org.keycloak.Config;
import org.keycloak.authentication.Authenticator;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.authentication.authenticators.browser.WebAuthnConditionalUIAuthenticator;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.models.credential.PasswordCredentialModel;
import org.keycloak.models.credential.WebAuthnCredentialModel;
import org.keycloak.provider.ProviderConfigProperty;

public class AutoCreateUsernamePasswordFormFactory implements AuthenticatorFactory {
    public static final String PROVIDER_ID = "auto-create-username-password-form";

    private static final AuthenticationExecutionModel.Requirement[] REQUIREMENT_CHOICES = {
        AuthenticationExecutionModel.Requirement.REQUIRED
    };

    @Override
    public Authenticator create(KeycloakSession session) {
        return new AutoCreateUsernamePasswordForm(session);
    }

    @Override
    public void init(Config.Scope config) {
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
    }

    @Override
    public void close() {
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getReferenceCategory() {
        return PasswordCredentialModel.TYPE;
    }

    @Override
    public Set<String> getOptionalReferenceCategories(KeycloakSession session) {
        return WebAuthnConditionalUIAuthenticator.isPasskeysEnabled(session)
            ? Collections.singleton(WebAuthnCredentialModel.TYPE_PASSWORDLESS)
            : AuthenticatorFactory.super.getOptionalReferenceCategories(session);
    }

    @Override
    public boolean isConfigurable() {
        return false;
    }

    @Override
    public AuthenticationExecutionModel.Requirement[] getRequirementChoices() {
        return REQUIREMENT_CHOICES;
    }

    @Override
    public String getDisplayType() {
        return "Auto-create Username Password Form";
    }

    @Override
    public String getHelpText() {
        return "Creates allowed-domain users during username/password login before validating the password.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return null;
    }

    @Override
    public boolean isUserSetupAllowed() {
        return false;
    }
}
