#   Copyright (c) 2010, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

class InvitationsController < Devise::InvitationsController

  before_filter :check_token, :only => [:edit]
  before_filter :check_if_invites_open, :only =>[:create]

  def new
    @sent_invitations = current_user.invitations_from_me.includes(:recipient)
    respond_to do |format|
      format.html do
        render :layout => false
      end
    end
  end

  def create
    aspect_id = params[:user].delete(:aspect_id)
    message = params[:user].delete(:invite_messages)
    emails = params[:user][:email].to_s.gsub(/\s/, '').split(/, */)
    #NOTE should we try and find users by email here? probs
    aspect = Aspect.find(aspect_id)
    invites = Invitation.batch_build(:sender => current_user, :aspect => aspect, :emails => emails, :service => 'email')

    flash[:notice] = extract_messages(invites)

    redirect_to :back
  end

  def update
    begin
      invitation_token = params[:user][:invitation_token]
      if invitation_token.nil? || invitation_token.blank?
        raise I18n.t('invitations.check_token.not_found')
      end
      user = User.find_by_invitation_token(params[:user][:invitation_token])
      user.accept_invitation!(params[:user])
      user.seed_aspects
    rescue Exception => e #What exception is this trying to rescue?  If it is ActiveRecord::NotFound, we should say so.
      raise e 
      user = nil
      record = e.record
      record.errors.delete(:person)

      flash[:error] = record.errors.full_messages.join(", ")
    end

    if user
      flash[:notice] = I18n.t 'registrations.create.success'
      sign_in_and_redirect(:user, user)
    else
      redirect_to accept_user_invitation_path(
        :invitation_token => params[:user][:invitation_token])
    end
  end

  def resend
    invitation = current_user.invitations_from_me.where(:id => params[:id]).first
    if invitation
      Resque.enqueue(Job::ResendInvitation, invitation.id)
      flash[:notice] = I18n.t('invitations.create.sent') + invitation.recipient.email
    end
    redirect_to :back
  end

  def email
    @invs = []
    @resource = User.find_by_invitation_token(params[:invitation_token])
    render 'devise/mailer/invitation_instructions', :layout => false
  end

  protected
  def check_token
    if User.find_by_invitation_token(params[:invitation_token]).nil?
      flash[:error] = I18n.t 'invitations.check_token.not_found'
      redirect_to root_url
    end
  end

  def check_if_invites_open
    unless AppConfig[:open_invitations]
      flash[:error] = I18n.t 'invitations.create.no_more'
      redirect_to :back
      return
    end
  end

  # @param invites [Array<Invitation>] Invitations to be sent.
  # @return [String] A full list of success and error messages.
  def extract_messages(invites)
    success_message = "Invites Successfully Sent to: "
    failure_message = "There was a problem with: "
    successes, failures = invites.partition{|x| x.persisted? }

    success_message += successes.map{|k| k.identifier }.join(', ')
    failure_message += failures.map{|k| k.identifier }.join(', ')

    messages = []
    messages << success_message if successes.present?
    messages << failure_message if failures.present?

    messages.join('\n')
  end
end
