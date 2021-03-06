# This module provides some standard logic for confirming email addresses, both upon
# signup and when an existing user changes her email address.
# 
# Include this module in your `User` model.
# 
#   add_column :users, :new_email, :string, after: :email
# 
# You can then use the `new_email` attribute in your account settings form like so:
# 
#   <%= form_for current_user do |f| %>
#     <% if f.object.email_change_unconfirmed? %>
#       <div>
#         Your email address (<%= f.object.new_email %>) has not been confirmed yet. In the
#         meantime, emails will continue to be sent to <%= f.object.email %>.
#       </div>
#     <% end %>
#   
#     <div>
#       <%= f.label 'Email address:' %>
#       <%= f.text_field :new_email %>
#     </div>
#   <% end %>
# 
# 

module Authlogic::ActsAsAuthentic::EmailToken::Confirmation
  # Call this when you have verified the user's email address. (Typically, as a result of
  # the user clicking the link in a confirmation email.)
  # 
  # Sets `email` to `new_email` and `new_email` to nil, if appropriate. Resets
  # the `email_token`.
  # 
  # You can use this for at least two purposes:
  # 
  # * verifying changes of address for existing accounts; and
  # * verifying new accounts.
  # 
  # For the latter purpose, this method looks for a method called `activate`, and if it
  # exists, calls it. (Or a method of a different name, if you configured
  # `activation_method`.)
  # 
  # This method doesn't save the user. If you want to save, call `#confirm_email!`.
  def confirm_email
    send(self.class.activation_method) if respond_to?(self.class.activation_method)
    if read_attribute(:new_email).present?
      self.email = new_email
      write_attribute :new_email, nil
    end
    reset_email_token
  end
  
  # Same as `#confirm_email`, but saves the user after.
  # (Via Authlogic's `save_without_session_maintenance`.)
  def confirm_email!
    confirm_email
    save_without_session_maintenance(validate: false)
  end
  
  # Sends a confirmation message.
  # 
  # By default, this methods assumes that the following method exists:
  # 
  #   UserMailer.email_confirmation(user, controller)
  # 
  # Also by default, this method calls `#deliver_now` on the message returned by
  # `UserMailer.email_confirmation`.
  # 
  # You can override either of these defaults by providing a block to this method. E.g.:
  # 
  #   # This would be in a controller action, so self refers to the controller.
  #   user.maybe_deliver_email_confirmation!(self) do
  #     MyOtherMailer.whatever_message(user).deliver_later
  #   end
  # 
  # Or, instead of providing a block, you can override the default names like so:
  # 
  #   acts_as_authentic do |c|
  #     c.confirmation_mailer_class = :MyOtherMailer
  #     c.confirmation_mailer_method = :a_method_name
  #   end
  def deliver_email_confirmation!(controller)
    reset_email_token!
    if block_given?
      yield
    else
      name = self.class.confirmation_mailer_class.to_s
      klass = name.split('::').inject(Object) do |mod, klass|
        mod.const_get klass
      end
      klass.send(self.class.confirmation_mailer_method, self, controller).deliver_now
    end
  end
  
  # Returns true if and only if:
  #   * `#email` changed during the previous save; or
  #   * `#new_email` changed during the previous save.
  def email_changed_previously?
    (previous_changes.has_key?(:email) and previous_changes[:email][1].present?) or
    (previous_changes.has_key?(:new_email) and previous_changes[:new_email][1].present?)
  end
  
  # Returns true if and only if new_email != email. Should only ever be true when user
  # changes email address. When user creates new account and activation is pending, this
  # is not true.
  def email_change_unconfirmed?
    read_attribute(:new_email).present? and (read_attribute(:new_email) != email)
  end
  
  # Sends a confirmation message if and only if `#email_changed_previously?` returns true.
  # (In other words, if `#email` or `#new_email` changed on the last save.) See
  # `#deliver_email_confirmation!` for config options.
  # 
  # Recommended usage looks something like this:
  #
  #   class UsersController < ApplicationController
  #     def create
  #       @user = User.new new_user_params
  #       if @user.save
  #         @user.deliver_email_confirmation! self
  #         redirect_to root_url, notice: 'Confirmation email sent.'
  #       else
  #         render action: :new
  #       end
  #     end
  #     
  #     def update
  #       if current_user.update_attributes existing_user_params
  #         if current_user.maybe_deliver_email_confirmation! self
  #           redirect_to edit_user_url, notice: 'Confirmation email sent.'
  #         else
  #           redirect_to edit_user_url, notice: 'Account settings saved.'
  #         end
  #       else
  #         render action: 'edit'
  #       end
  #     end
  #     
  #     private
  #     
  #     def existing_user_params
  #       params.require(:user).permit(:new_email, :password, :password_confirmation)
  #     end
  #   
  #     def new_user_params
  #       params.require(:user).permit(:email, :password, :password_confirmation)
  #     end
  #   end
  def maybe_deliver_email_confirmation!(controller)
    if email_changed_previously?
      deliver_email_confirmation! controller
      true
    else
      false
    end
  end
  
  # Returns the contents of the `new_email` column. Or, if that column is blank, returns
  # the contents of the `email` column instead. Designed to be called from an account
  # settings form, e.g.:
  # 
  #   <%= f.text_field :new_email %>
  def new_email
    e = read_attribute :new_email
    e.present? ? e : email
  end
  # Rails' text_field helper calls new_email_before_typecast.
  alias_method :new_email_before_type_cast, :new_email
  
  # Like a normal attribute setter, except it is a no-op if the value is equal to the
  # current value of #email.
  def new_email=(e)
    if e.present? and e != email
      write_attribute :new_email, e
    end
  end
end