class Notifier < ActionMailer::Base
  layout 'notification'
  default :from => AppConfig.notification_email

  helper :application

  def give_advice(user, group, question, following = false)
    @user = user
    @group = group
    @question = question
    @following = following

    @domain = group.domain

    scope = "mailers.notifications.give_advice"

    if following
      subject = I18n.t("friend_subject", :scope => scope,
                     :question_title => question.title)
    else
      subject = I18n.t("subject", :scope => scope,
                     :question_title => question.title)
    end

    mail(:to => user.email, :subject => subject)
  end

  def new_answer(user, group, answer, following = false)
    @user = user
    @group = group
    @answer = answer
    @following = following

    @domain = group.domain
    @question = @answer.question

    scope = "mailers.notifications.new_answer"

    if user == answer.question.user
      subject = I18n.t("subject_owner", :scope => scope,
                       :title => answer.question.title,
                       :login => answer.user.login)
    elsif following
      subject = I18n.t("subject_friend", :scope => scope,
                       :title => answer.question.title,
                       :login => answer.user.login)
    else
      subject = I18n.t("subject_other", :scope => scope,
                       :title => answer.question.title,
                       :login => answer.user.login)
    end

    mail(:to => user.email, :subject => subject)
  end

  def new_comment(user, group, comment, question)
    @user = user
    @group = group
    @comment = comment
    @question = question

    @domain = group.domain

    subject = I18n.t("mailers.notifications.new_comment.subject",
                     :login => comment.user.login, :group => group.name)

    mail(:to => user.email, :subject => subject)
  end

  def new_feedback(user, title, content, email, ip)
    @user = user
    @title = title
    @content = content
    @email = email
    @ip = ip

    recipients = AppConfig.exception_notification["exception_recipients"]
    subject = "feedback: #{title}"

    mail(:to => recipients, :subject => subject)
  end

  def follow(user, followed)
    @user = user
    @followed = followed

    subject = I18n.t("mailers.notifications.follow.subject",
                     :login => user.login, :app => AppConfig.application_name)

    mail(:to => followed.email, :subject => subject)
  end

  def earned_badge(user, group, badge)
    @user = user
    @group = group
    @badge = badge

    subject = I18n.t("mailers.notifications.earned_badge.subject",
                     :group => group.name)

    mail(:to => user.email, :subject => subject)
  end

  def favorited(user, group, question)
    @user = user
    @group = group
    @question = question

    subject = I18n.t("mailers.notifications.favorited.subject",
                     :login => user.login)

    mail(:to => question.user.email, :subject => subject)
  end

  def report(user, report)
    @user = user
    @report = report

    subject = I18n.t("mailers.notifications.report.subject",
                     :group => report.group.name,
                     :app => AppConfig.application_name)

    mail(:to => user.email, :subject => subject)
  end
end